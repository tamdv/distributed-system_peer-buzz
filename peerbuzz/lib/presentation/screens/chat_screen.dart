import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../../data/services/p2p_service.dart';
import '../../core/models/models.dart';

class ChatScreen extends StatefulWidget {
  final Peer? targetPeer;
  const ChatScreen({super.key, required this.targetPeer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  final List<BaseMessage> _chatHistory = [];
  final ScrollController _chatController = ScrollController();
  final Map<String, double> _transferProgress = {}; // transferId -> progress
  StreamSubscription? _errorSubscription;

  @override
  void initState() {
    super.initState();
    final p2p = Provider.of<P2PService>(context, listen: false);

    // Nạp lịch sử tin nhắn cũ
    final String chatId =
        widget.targetPeer == null ? 'group' : widget.targetPeer!.id;
    p2p.getPeerHistory(chatId).then((history) {
      if (mounted) {
        setState(() {
          _chatHistory.clear();
          _chatHistory.addAll(history);
          // Loại bỏ tin nhắn trùng lặp nếu có (dựa trên senderId + timestamp)
          final seen = <String>{};
          _chatHistory.retainWhere((m) {
            final key = '${m.senderId}_${m.lamportTimestamp}';
            return seen.add(key);
          });
          _chatHistory.sort(
              (a, b) => a.lamportTimestamp.compareTo(b.lamportTimestamp));
        });
        _scrollToBottom();
      }
    });

    // Listen to messages
    p2p.messages.listen((msg) {
      bool isRelevant = false;
      if (widget.targetPeer == null) {
        // Chế độ Broadcast
        isRelevant = (msg.type == MessageType.broadcastMsg);
      } else {
        // Chế độ 1-1
        isRelevant = (msg.type == MessageType.chatMsg && (msg.senderId == widget.targetPeer!.id || msg.senderId == p2p.localPeer.id));
      }

      if (mounted && isRelevant) {
        p2p.markAsRead(widget.targetPeer == null ? 'group' : widget.targetPeer!.id);
        setState(() {
          _chatHistory.add(msg);
          // Sắp xếp theo Lamport Timestamp
          _chatHistory.sort((a, b) => a.lamportTimestamp.compareTo(b.lamportTimestamp));
        });
        _scrollToBottom();
      }
    });

    // Listen to file progress
    p2p.fileProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _transferProgress[progress.transferId] = progress.progress;
          if (progress.isCompleted) {
            // Keep it for a bit then could remove or just keep at 1.0
          }
        });
      }
    });

    // Listen to network errors
    _errorSubscription = p2p.errorStream.listen((errorMsg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatController.hasClients) {
        _chatController.animateTo(
          _chatController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    if (_msgController.text.isEmpty) return;
    final p2p = Provider.of<P2PService>(context, listen: false);
    if (widget.targetPeer == null) {
      p2p.broadcastMessage(_msgController.text);
    } else {
      p2p.sendMessage(widget.targetPeer!.id, _msgController.text);
    }
    _msgController.clear();
  }

  void _pickFile() async {
    final result = await FilePicker.pickFiles();
    if (result != null && result.files.single.path != null) {
      final p2p = Provider.of<P2PService>(context, listen: false);
      p2p.sendFile(widget.targetPeer?.id, result.files.single.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p2p = Provider.of<P2PService>(context);
    final title = widget.targetPeer == null ? 'Phòng chung' : 'Chat với ${widget.targetPeer!.name}';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _chatController,
              itemCount: _chatHistory.length,
              itemBuilder: (context, index) {
                final msg = _chatHistory[index];
                final isMe = msg.senderId == p2p.localPeer.id;
                final transferId = msg.payload['transfer_id'];
                final progress = transferId != null ? _transferProgress[transferId] : null;

                return Column(
                  children: [
                    Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(left: 15, right: 15, top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueGrey.withOpacity(0.5) : Colors.green.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          msg.senderName,
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ),
                    ),
                    Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(minWidth: 100, maxWidth: MediaQuery.of(context).size.width * 0.75),
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blueGrey : const Color.fromARGB(255, 68, 108, 70),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.payload['content'],
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                            ),
                            if (isMe)
                              const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Icon(Icons.check_circle, size: 14, color: Colors.white70),
                                ),
                              ),
                            if (progress != null && progress < 1.0) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white24,
                                color: Colors.orange,
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 10, color: Colors.white70),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (msg.payload['is_file'] == true)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
                        child: Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: () => OpenFilex.open(msg.payload['path']),
                            icon: const Icon(Icons.insert_drive_file),
                            label: Text('Mở: ${msg.payload['file_name'] ?? "File"}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _pickFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: 'Nhập tin nhắn...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 236, 97, 23),
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.white), onPressed: _send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
