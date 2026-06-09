import 'dart:convert';

enum MessageType {
  join, // Peer -> Bootstrap: Tham gia mạng
  leave, // Peer -> Bootstrap: Rời mạng chủ động
  heartbeat, // Peer -> Bootstrap: Duy trì online
  chatReq, // Peer A -> Peer B: Yêu cầu chat
  chatMsg, // Peer -> Peer: Gửi tin nhắn
  broadcastMsg, // Peer -> All: Chat nhóm
  fileReq, // Yêu cầu gửi file
  fileChunk, // Khối dữ liệu file
  storeFor, // Lưu tin nhắn hộ cho peer offline
  gossipDown, // Peer -> Peer: Lan truyền nút bị sập
  updateList // Bootstrap -> Peer: Cập nhật danh sách online
}

class Peer {
  final String id;
  final String ip;
  final int port;
  final String name;
  DateTime? lastSeen;

  Peer({
    required this.id,
    required this.ip,
    required this.port,
    required this.name,
    this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ip': ip,
        'port': port,
        'name': name,
      };

  factory Peer.fromJson(Map<String, dynamic> json) => Peer(
        id: json['id'],
        ip: json['ip'],
        port: json['port'],
        name: json['name'],
      );

  @override
  String toString() => '$name ($ip:$port)';
}

class BaseMessage {
  final MessageType type;
  final String senderId;
  final String senderName;
  final int lamportTimestamp;
  final Map<String, dynamic> payload;

  BaseMessage({
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.lamportTimestamp,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'sender_id': senderId,
        'sender_name': senderName,
        'lamport_timestamp': lamportTimestamp,
        'payload': payload,
      };

  factory BaseMessage.fromJson(Map<String, dynamic> json) => BaseMessage(
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.chatMsg,
        ),
        senderId: json['sender_id'] ?? 'unknown',
        senderName: json['sender_name'] ?? 'unknown',
        lamportTimestamp: json['lamport_timestamp'] ?? 0,
        payload: json['payload'] ?? {},
      );

  String encode() => jsonEncode(toJson()) + '\n';
}

class FileProgress {
  final String transferId; // unique id for each file transfer session
  final String fileName;
  final double progress; // 0.0 to 1.0
  final bool isSender;
  final bool isCompleted;

  FileProgress({
    required this.transferId,
    required this.fileName,
    required this.progress,
    required this.isSender,
    this.isCompleted = false,
  });
}
