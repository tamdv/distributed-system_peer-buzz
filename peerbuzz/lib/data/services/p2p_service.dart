import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/models.dart';
import '../../core/protocol/lamport_clock.dart';
import '../../core/network/encryption_helper.dart';
import 'storage_service.dart';

class P2PService with ChangeNotifier, WidgetsBindingObserver {
  late Peer localPeer;
  final LamportClock clock = LamportClock();
  final Map<String, Peer> onlinePeers = {};
  final Set<String> _seenMessageIds = {};
  final Map<String, Map<int, List<int>>> _incomingFiles = {}; // transferId -> chunkIndex -> bytes
  final Map<String, int> unreadCounts = {}; // peerId or 'group' -> count
  final Map<String, List<BaseMessage>> chatHistory = {}; // peerId or 'group' -> list
  final Map<String, List<BaseMessage>> _storedMessages =
      {}; // targetId -> messages

  ServerSocket? _serverSocket;
  Socket? _bootstrapSocket;
  String? _lastBootstrapIp;
  int? _lastBootstrapPort;

  final StreamController<BaseMessage> _messageStreamController =
      StreamController.broadcast();
  Stream<BaseMessage> get messages => _messageStreamController.stream;

  final StreamController<FileProgress> _fileProgressController =
      StreamController.broadcast();
  Stream<FileProgress> get fileProgress => _fileProgressController.stream;

  final StreamController<String> _errorStreamController =
      StreamController.broadcast();
  Stream<String> get errorStream => _errorStreamController.stream;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Khởi tạo Peer với Tên và kết nối tới Bootstrap
  Future<void> init(String name, String bootstrapIp, int bootstrapPort) async {
    final id = const Uuid().v4();

    // Tìm IP local (Ưu tiên dải IP cùng subnet với Bootstrap Server)
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    String ip = '127.0.0.1';

    if (interfaces.isNotEmpty) {
      // Tìm interface có IP khớp 2 số đầu với bootstrapIp (ví dụ: 192.168.x.x)
      final bootstrapPrefix = bootstrapIp.split('.').take(2).join('.');
      try {
        ip = interfaces
            .expand((i) => i.addresses)
            .firstWhere((a) => a.address.startsWith(bootstrapPrefix))
            .address;
      } catch (_) {
        // Nếu không thấy dải khớp, lấy IP đầu tiên không phải loopback
        ip = interfaces.first.addresses.first.address;
      }
    }

    // Mở cổng ngẫu nhiên để lắng nghe
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = _serverSocket!.port;

    localPeer = Peer(id: id, ip: ip, port: port, name: name);

    // Lắng nghe kết nối đến từ các Peer khác
    _serverSocket!.listen(_handleIncomingConnection);

    // Kết nối tới Bootstrap Server
    _lastBootstrapIp = bootstrapIp;
    _lastBootstrapPort = bootstrapPort;
    await _connectToBootstrap(bootstrapIp, bootstrapPort);

    _isInitialized = true;
    notifyListeners();

    // Nạp lại lịch sử tin nhắn từ bộ nhớ
    await _loadHistory();

    // Bắt đầu gửi Heartbeat định kỳ
    _startHeartbeat(bootstrapIp, bootstrapPort);

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed, checking socket connection...');
      _checkAndReconnect();
    } else if (state == AppLifecycleState.paused) {
      debugPrint('App paused, OS might suspend socket.');
    }
  }

  void _checkAndReconnect() async {
    if (_lastBootstrapIp == null || _lastBootstrapPort == null) return;
    
    if (_bootstrapSocket == null) {
      debugPrint('Socket is null on resume, reconnecting...');
      await _connectToBootstrap(_lastBootstrapIp!, _lastBootstrapPort!);
      return;
    }
    
    // Test current connection by sending a heartbeat
    try {
      final hb = BaseMessage(
        type: MessageType.heartbeat,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.value,
        payload: localPeer.toJson(),
      );
      _bootstrapSocket!.write(hb.encode());
    } catch (e) {
      debugPrint('Socket write failed on resume, reconnecting: $e');
      _bootstrapSocket?.close();
      _bootstrapSocket = null;
      await _connectToBootstrap(_lastBootstrapIp!, _lastBootstrapPort!);
    }
  }

  Future<void> _connectToBootstrap(String ip, int port) async {
    try {
      _bootstrapSocket = await Socket.connect(ip, port);

      // Gửi gói JOIN
      final joinMsg = BaseMessage(
        type: MessageType.join,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.tick(),
        payload: localPeer.toJson(),
      );
      _bootstrapSocket!.write(joinMsg.encode());

      // Lắng nghe cập nhật danh sách Peer từ Bootstrap
      _bootstrapSocket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((raw) {
        try {
          final json = jsonDecode(raw);
          final msg = BaseMessage.fromJson(json);

          if (msg.type == MessageType.updateList) {
            final List peersJson = msg.payload['peers'];
            onlinePeers.clear();
            for (var p in peersJson) {
              final peer = Peer.fromJson(p);
              if (peer.id != localPeer.id) {
                onlinePeers[peer.id] = peer;
                // Nếu thấy peer này online, kiểm tra xem có tin nhắn nào đang lưu hộ không
                _checkAndDeliverStoredMessages(peer.id);
              }
            }
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Error decoding bootstrap message: $e');
        }
      });
    } catch (e) {
      debugPrint('Error connecting to Bootstrap: $e');
    }
  }

  void _handleIncomingConnection(Socket client) {
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((raw) async {
      try {
        final json = jsonDecode(raw);
        final msg = BaseMessage.fromJson(json);

        debugPrint(
            'Received P2P message: ${msg.toJson()} from ${msg.senderId}');

        // Cập nhật Lamport Clock khi nhận tin
        clock.update(msg.lamportTimestamp);

        // Tránh xử lý lặp lại tin nhắn Broadcast
        if (msg.type == MessageType.broadcastMsg) {
          final msgId = msg.payload['msg_id'];
          if (_seenMessageIds.contains(msgId)) return;
          _seenMessageIds.add(msgId);
        }

        // Đưa tin nhắn vào luồng xử lý UI
        if (msg.type == MessageType.chatMsg ||
            msg.type == MessageType.broadcastMsg) {
          if (msg.payload['is_encrypted'] == true) {
            final encryptedContent = msg.payload['content'];
            msg.payload['content'] = await EncryptionHelper.decrypt(encryptedContent);
          }
        }

        if (msg.type == MessageType.fileChunk) {
          _handleFileChunk(msg);
        }

        if (msg.type == MessageType.storeFor) {
          _handleStoreFor(msg);
          return; // Không hiển thị tin nhắn lưu hộ lên UI của người trung gian
        }

        // Chỉ lưu và thông báo tin nhắn Chat hoặc Broadcast
        if (msg.type == MessageType.chatMsg || msg.type == MessageType.broadcastMsg) {
          _messageStreamController.add(msg);

          // Cập nhật số tin nhắn chưa đọc
          final String unreadKey = msg.type == MessageType.broadcastMsg || (msg.type == MessageType.chatMsg && msg.payload['is_broadcast'] == true)
              ? 'group'
              : msg.senderId;

          // Lưu vào lịch sử
          _saveToHistory(unreadKey, msg);

          unreadCounts[unreadKey] = (unreadCounts[unreadKey] ?? 0) + 1;
          notifyListeners();
        }

        if (msg.type == MessageType.gossipDown) {
          final targetId = msg.payload['target_id'];
          if (onlinePeers.containsKey(targetId)) {
            debugPrint(
                'Gossip received: Peer $targetId is down. Removing from list.');
            onlinePeers.remove(targetId);
            notifyListeners();
          }
        }
      } catch (e) {
        debugPrint('Error handling P2P data: $e');
      }
    });
  }

  /// Gửi tin nhắn trực tiếp tới một Peer
  Future<void> sendMessage(String targetPeerId, String content) async {
    final target = onlinePeers[targetPeerId];
    if (target == null) return;

    try {
      final socket = await Socket.connect(target.ip, target.port, timeout: const Duration(seconds: 5));
      final msg = BaseMessage(
        type: MessageType.chatMsg,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.tick(),
        payload: {
          'content': await EncryptionHelper.encrypt(content),
          'is_encrypted': true,
        },
      );

      socket.write(msg.encode());
      await socket.flush();
      await socket.close();

      // Đồng thời tự thêm vào stream để UI hiển thị (nếu cần)
      // Fix bug: Hiển thị plaintext cho người gửi
      msg.payload['content'] = content;
      _messageStreamController.add(msg);
      _saveToHistory(targetPeerId, msg);
    } catch (e) {
      debugPrint('Failed to send message to ${target.name}: $e');
      _errorStreamController.add('Không thể kết nối trực tiếp đến ${target.name}. Đang thử nhờ láng giềng lưu hộ...');
      // Khi kết nối thất bại, thử Store-and-forward cho một láng giềng khác
      _attemptStoreAndForward(targetPeerId, content);
      // Đồng thời kích hoạt Gossip
      _gossipAboutFailedPeer(targetPeerId);
    }
  }

  Future<void> _attemptStoreAndForward(String targetId, String content) async {
    final neighbors =
        onlinePeers.values.where((p) => p.id != targetId).toList();
    if (neighbors.isEmpty) return;

    final relay = (neighbors..shuffle()).first;
    debugPrint('Attempting store-and-forward for $targetId via ${relay.name}');

    try {
      final socket = await Socket.connect(relay.ip, relay.port, timeout: const Duration(seconds: 5));
      final msg = BaseMessage(
        type: MessageType.storeFor,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.tick(),
        payload: {
          'target_id': targetId,
          'original_content': content,
        },
      );
      socket.write(msg.encode());
      await socket.flush();
      await socket.close();
    } catch (e) {
      debugPrint('Store-and-forward failed: $e');
    }
  }

  void _handleStoreFor(BaseMessage msg) {
    final targetId = msg.payload['target_id'];
    final originalContent = msg.payload['original_content'];

    if (!_storedMessages.containsKey(targetId)) {
      _storedMessages[targetId] = [];
    }

    // Tạo tin nhắn giả lập từ người gửi gốc để lưu
    final originalMsg = BaseMessage(
      type: MessageType.chatMsg,
      senderId: msg.senderId,
      senderName: msg.senderName,
      lamportTimestamp: msg.lamportTimestamp,
      payload: {'content': originalContent, 'is_stored': true},
    );

    if (_storedMessages[targetId]!.length >= 100) {
      _storedMessages[targetId]!.removeAt(0); // Giới hạn bộ nhớ, xóa tin cũ nhất
    }
    _storedMessages[targetId]!.add(originalMsg);
    debugPrint('Stored a message for offline peer: $targetId (Total: ${_storedMessages[targetId]!.length})');
  }

  void _checkAndDeliverStoredMessages(String peerId) async {
    if (!_storedMessages.containsKey(peerId) ||
        _storedMessages[peerId]!.isEmpty) return;

    final peer = onlinePeers[peerId];
    if (peer == null) return;

    debugPrint(
        'Delivering ${_storedMessages[peerId]!.length} messages to $peerId');
    final messagesToDeliver = List<BaseMessage>.from(_storedMessages[peerId]!);
    _storedMessages[peerId]!.clear();

    for (var msg in messagesToDeliver) {
      try {
        final socket = await Socket.connect(peer.ip, peer.port);
        socket.write(msg.encode());
        await socket.flush();
        await socket.close();
      } catch (e) {
        debugPrint('Failed to deliver stored message: $e');
        // Nếu thất bại lại, nạp ngược vào buffer
        _storedMessages[peerId]!.add(msg);
      }
    }
  }

  /// Gửi tin nhắn tới tất cả các Peer đang online
  Future<void> broadcastMessage(String content) async {
    final msgId = const Uuid().v4();
    final msg = BaseMessage(
      type: MessageType.broadcastMsg,
      senderId: localPeer.id,
      senderName: localPeer.name,
      lamportTimestamp: clock.tick(),
      payload: {
        'msg_id': msgId,
        'content': await EncryptionHelper.encrypt(content),
        'is_encrypted': true,
      },
    );

    _seenMessageIds.add(msgId);

    // Fix bug: Hiển thị plaintext cho người gửi
    final displayMsg = BaseMessage(
      type: msg.type,
      senderId: msg.senderId,
      senderName: msg.senderName,
      lamportTimestamp: msg.lamportTimestamp,
      payload: Map.from(msg.payload)..['content'] = content,
    );
    _messageStreamController.add(displayMsg);
    _saveToHistory('group', displayMsg);

    // Gửi tới tất cả các láng giềng
    for (var peer in onlinePeers.values) {
      try {
        final socket = await Socket.connect(peer.ip, peer.port,
            timeout: const Duration(seconds: 2));
        socket.write(msg.encode());
        await socket.flush();
        await socket.close();
      } catch (e) {
        debugPrint('Broadcast failed for ${peer.name}: $e');
        _errorStreamController.add('Không thể gửi tin nhóm tới ${peer.name}');
      }
    }
  }

  /// Truyền file P2P bằng cách chia nhỏ thành các khối (Chunks)
  Future<void> sendFile(String? targetPeerId, String filePath) async {
    final List<Peer> targets = [];
    if (targetPeerId == null) {
      targets.addAll(onlinePeers.values);
    } else if (onlinePeers.containsKey(targetPeerId)) {
      targets.add(onlinePeers[targetPeerId]!);
    }

    if (targets.isEmpty) return;

    final file = File(filePath);
    final fileName = file.path.split('/').last;
    final bytes = await file.readAsBytes();
    const chunkSize = 32768; // 32KB
    final totalChunks = (bytes.length / chunkSize).ceil();
    final transferId = const Uuid().v4();

    final infoMsg = BaseMessage(
      type:
          targetPeerId == null ? MessageType.broadcastMsg : MessageType.chatMsg,
      senderId: localPeer.id,
      senderName: localPeer.name,
      lamportTimestamp: clock.tick(),
      payload: {
        'content':
            'Đang gửi file: $fileName (${(bytes.length / 1024).toStringAsFixed(1)} KB)...',
        'is_file_info': true,
        'file_name': fileName,
        'transfer_id': transferId,
      },
    );

    _messageStreamController.add(infoMsg);
    _saveToHistory(targetPeerId ?? 'group', infoMsg);

    // Băm file trong Isolate để tránh block UI
    final base64Chunks = await compute(_processFileChunks, {
      'bytes': bytes,
      'chunkSize': chunkSize,
    });

    for (int i = 0; i < totalChunks; i++) {
      final chunkData = base64Chunks[i];

      final msg = BaseMessage(
        type: MessageType.fileChunk,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.tick(),
        payload: {
          'file_name': fileName,
          'transfer_id': transferId,
          'chunk_index': i,
          'total_chunks': totalChunks,
          'data': chunkData,
          'is_broadcast': targetPeerId == null,
        },
      );

      final double progress = (i + 1) / totalChunks;
      _fileProgressController.add(FileProgress(
        transferId: transferId,
        fileName: fileName,
        progress: progress,
        isSender: true,
        isCompleted: i == totalChunks - 1,
      ));

      for (var target in targets) {
        try {
          final socket = await Socket.connect(target.ip, target.port,
              timeout: const Duration(seconds: 5));
          socket.write(msg.encode());
          await socket.flush();
          await socket.close();
        } catch (e) {
          debugPrint('Failed to send chunk $i to ${target.name}: $e');
          _errorStreamController.add('Lỗi gửi file tới ${target.name}');
        }
      }
      // Delay nhỏ để tránh nghẽn socket và cho phép UI cập nhật
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  void _handleFileChunk(BaseMessage msg) async {
    final fileName = msg.payload['file_name'];
    final transferId = msg.payload['transfer_id'] ?? fileName;
    final chunkIndex = msg.payload['chunk_index'];
    final totalChunks = msg.payload['total_chunks'];
    final isBroadcast = msg.payload['is_broadcast'] == true;
    final data = base64Decode(msg.payload['data']);

    if (!_incomingFiles.containsKey(transferId)) {
      _incomingFiles[transferId] = {};
    }

    _incomingFiles[transferId]![chunkIndex] = data;

    final double progress = _incomingFiles[transferId]!.length / totalChunks;
    _fileProgressController.add(FileProgress(
      transferId: transferId,
      fileName: fileName,
      progress: progress,
      isSender: false,
      isCompleted: _incomingFiles[transferId]!.length == totalChunks,
    ));

    if (_incomingFiles[transferId]!.length == totalChunks) {
      // Đã nhận đủ tất cả các mảnh, tiến hành ghép file theo đúng thứ tự
      final directory = await getApplicationDocumentsDirectory();
      final savePath = '${directory.path}/$fileName';
      final file = File(savePath);

      final List<int> allBytes = [];
      for (int i = 0; i < totalChunks; i++) {
        if (_incomingFiles[transferId]!.containsKey(i)) {
          allBytes.addAll(_incomingFiles[transferId]![i]!);
        }
      }

      await file.writeAsBytes(allBytes);
      _incomingFiles.remove(transferId);

      final notificationMsg = BaseMessage(
        type: isBroadcast ? MessageType.broadcastMsg : MessageType.chatMsg,
        senderId: msg.senderId,
        senderName: msg.senderName,
        lamportTimestamp: clock.tick(),
        payload: {
          'content': 'Đã nhận xong file: $fileName',
          'is_file': true,
          'file_name': fileName,
          'path': savePath,
          'is_broadcast': isBroadcast,
        },
      );

      _messageStreamController.add(notificationMsg);

      // Cập nhật số tin nhắn chưa đọc cho thông báo nhận file
      final String unreadKey = isBroadcast ? 'group' : msg.senderId;

      _saveToHistory(unreadKey, notificationMsg);

      unreadCounts[unreadKey] = (unreadCounts[unreadKey] ?? 0) + 1;
      notifyListeners();
    }
  }

  void markAsRead(String id) {
    if (unreadCounts.containsKey(id)) {
      unreadCounts[id] = 0;
      notifyListeners();
    }
  }

  Future<void> _loadHistory() async {
    // Load group history
    chatHistory['group'] = await StorageService.loadMessages('group');

    // Ở bản demo này, chúng ta chưa biết hết danh sách peer cũ,
    // nhưng khi một peer online, chúng ta sẽ load sau hoặc load tất cả file chat_*.json
    // Để đơn giản, ta sẽ load theo nhu cầu hoặc load một danh sách cache.
    // Tạm thời chỉ load Group. Lịch sử peer cá nhân sẽ được load khi có tương tác hoặc login.
    notifyListeners();
  }

  Future<List<BaseMessage>> getPeerHistory(String peerId) async {
    if (!chatHistory.containsKey(peerId)) {
      chatHistory[peerId] = await StorageService.loadMessages(peerId);
      notifyListeners();
    }
    return chatHistory[peerId]!;
  }

  void _saveToHistory(String id, BaseMessage msg) {
    if (!chatHistory.containsKey(id)) {
      chatHistory[id] = [];
    }
    chatHistory[id]!.add(msg);
    StorageService.saveMessages(id, chatHistory[id]!);
    notifyListeners();
  }

  Future<void> logout() async {
    if (_bootstrapSocket != null) {
      final leaveMsg = BaseMessage(
        type: MessageType.leave,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.tick(),
        payload: {},
      );
      try {
        _bootstrapSocket!.write(leaveMsg.encode());
        await _bootstrapSocket!.flush();
      } catch (_) {}
    }
    _serverSocket?.close();
    _bootstrapSocket?.close();
    _isInitialized = false;
    onlinePeers.clear();
    notifyListeners();
  }

  /// Lan truyền tin đồn rằng một Peer đã sập tới các láng giềng khác
  void _gossipAboutFailedPeer(String failedPeerId) async {
    if (!onlinePeers.containsKey(failedPeerId)) return;

    debugPrint('Gossiping about failed peer: $failedPeerId');
    onlinePeers.remove(failedPeerId);
    notifyListeners();

    final gossipMsg = BaseMessage(
      type: MessageType.gossipDown,
      senderId: localPeer.id,
      senderName: localPeer.name,
      lamportTimestamp: clock.tick(),
      payload: {'target_id': failedPeerId},
    );

    // Gửi tới tối đa 3 láng giềng ngẫu nhiên
    final neighbors = onlinePeers.values.toList()..shuffle();
    for (var neighbor in neighbors.take(3)) {
      try {
        final socket = await Socket.connect(neighbor.ip, neighbor.port,
            timeout: const Duration(seconds: 2));
        socket.write(gossipMsg.encode());
        await socket.flush();
        await socket.close();
      } catch (_) {
        // Nếu không gửi được tới láng giềng, có thể láng giềng đó cũng đã sập
      }
    }
  }

  void _startHeartbeat(String bIp, int bPort) {
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_bootstrapSocket == null) {
        debugPrint('Bootstrap connection lost. Attempting to reconnect...');
        await _connectToBootstrap(bIp, bPort);
        return;
      }

      final hb = BaseMessage(
        type: MessageType.heartbeat,
        senderId: localPeer.id,
        senderName: localPeer.name,
        lamportTimestamp: clock.value,
        payload: localPeer.toJson(),
      );
      try {
        _bootstrapSocket!.write(hb.encode());
      } catch (e) {
        debugPrint('Heartbeat failed: $e');
        _bootstrapSocket = null;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serverSocket?.close();
    _bootstrapSocket?.close();
    _messageStreamController.close();
    _fileProgressController.close();
    _errorStreamController.close();
    super.dispose();
  }
}

// Top-level function để chạy trong Isolate
List<String> _processFileChunks(Map<String, dynamic> args) {
  final bytes = args['bytes'] as List<int>;
  final chunkSize = args['chunkSize'] as int;
  final totalChunks = (bytes.length / chunkSize).ceil();
  final List<String> chunks = [];
  
  for (int i = 0; i < totalChunks; i++) {
    final start = i * chunkSize;
    final end =
        (start + chunkSize > bytes.length) ? bytes.length : start + chunkSize;
    chunks.add(base64Encode(bytes.sublist(start, end)));
  }
  
  return chunks;
}
