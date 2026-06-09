import 'dart:io';
import 'dart:convert';
import 'dart:async';

void main() async {
  final server = BootstrapServer();
  await server.start(port: 8888);
}

class PeerInfo {
  final String id;
  final String ip;
  final int port;
  final String name;
  DateTime lastSeen;

  PeerInfo(this.id, this.ip, this.port, this.name, this.lastSeen);

  Map<String, dynamic> toJson() =>
      {'id': id, 'ip': ip, 'port': port, 'name': name};
}

class BootstrapServer {
  final Map<String, PeerInfo> _activePeers = {};
  final Duration _timeout = Duration(seconds: 60);

  Future<void> start({int port = 8888}) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print('==============================================');
    print('🚀 PeerBuzz Bootstrap Server is running');
    print('📍 Address: ${server.address.address}:${server.port}');
    print('⏱  Timeout policy: ${_timeout.inSeconds}s');
    print('==============================================');

    Timer.periodic(Duration(seconds: 2), (timer) => _checkTimeouts());

    await for (var client in server) {
      _handleClient(client);
    }
  }

  void _handleClient(Socket client) {
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((raw) {
      try {
        final msg = jsonDecode(raw);
        _processMessage(msg, client);
      } catch (e) {
        print('Error decoding message: $e');
      }
    }, onDone: () => client.close(), onError: (e) => client.close());
  }

  void _processMessage(Map<String, dynamic> msg, Socket client) {
    final type = msg['type'];
    final senderId = msg['sender_id'];
    final payload = msg['payload'] ?? {};

    switch (type) {
      case 'join':
        print(
            '(+) Peer JOIN: ${payload['name']} ($senderId) at ${client.remoteAddress.address}');
        _updatePeer(senderId, payload, client.remoteAddress.address);
        _sendPeerList(client);
        break;

      case 'heartbeat':
        // Cập nhật trạng thái sống mà không cần in log quá nhiều
        _updatePeer(senderId, payload, client.remoteAddress.address);
        _sendPeerList(client); // Trả về danh sách mới nhất để Peer cập nhật
        break;

      case 'leave':
        print('(-) Peer LEAVE: $senderId');
        _activePeers.remove(senderId);
        break;

      case 'gossipDown':
        final targetId = payload['target_id'];
        if (_activePeers.containsKey(targetId)) {
          print(
              '(!) Gossip received: Node $targetId might be down. Verifying...');
          // Trong mô hình tin cậy, ta có thể xóa luôn hoặc đợi Timeout
          // Ở đây ta xóa luôn để tăng tốc độ hội tụ mạng
          _activePeers.remove(targetId);
        }
        break;
    }
  }

  void _updatePeer(String id, Map<String, dynamic> payload, String remoteIp) {
    _activePeers[id] = PeerInfo(id, payload['ip'] ?? remoteIp,
        payload['port'] ?? 0, payload['name'] ?? 'Unknown', DateTime.now());
  }

  void _sendPeerList(Socket client) {
    // Trả về tối đa 10 peer ngẫu nhiên để tạo mạng phủ phi cấu trúc (Unstructured)
    // Nếu mạng nhỏ, trả về tất cả.
    final allPeers = _activePeers.values.map((p) => p.toJson()).toList();

    final response = {
      'type': 'updateList',
      'sender_id': 'bootstrap',
      'sender_name': 'Bootstrap Server',
      'lamport_timestamp': 0,
      'payload': {'peers': allPeers}
    };

    try {
      client.write(jsonEncode(response) + '\n');
    } catch (e) {
      print('Error sending peer list: $e');
    }
  }

  void _checkTimeouts() {
    final now = DateTime.now();
    final expiredIds = _activePeers.entries
        .where((e) => now.difference(e.value.lastSeen) > _timeout)
        .map((e) => e.key)
        .toList();

    for (var id in expiredIds) {
      print('(X) Peer TIMEOUT: $id. Removing from active view.');
      _activePeers.remove(id);
    }
  }
}
