import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/p2p_service.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p2p = Provider.of<P2PService>(context);
    final peers = p2p.onlinePeers.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('PeerBuzz: ${p2p.localPeer.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: peers.isEmpty
          ? const Center(child: Text('Chưa có peer nào online'))
          : ListView(
              children: [
                ListTile(
                  leading: Stack(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color.fromARGB(255, 236, 97, 23),
                        child: Icon(Icons.groups, color: Colors.white),
                      ),
                      if ((p2p.unreadCounts['group'] ?? 0) > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: const Text('Phòng chung (Broadcast)'),
                  subtitle: const Text('Gửi tin nhắn tới tất cả mọi người'),
                  onTap: () {
                    p2p.markAsRead('group');
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChatScreen(
                          targetPeer: null, // null nghĩa là Broadcast
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                ...peers.map((peer) {
                  final unreadCount = p2p.unreadCounts[peer.id] ?? 0;
                  return ListTile(
                    leading: Stack(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person)),
                        if (unreadCount > 0)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(peer.name),
                    subtitle: Text('${peer.ip}:${peer.port}'),
                    onTap: () {
                      p2p.markAsRead(peer.id);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(targetPeer: peer)),
                      );
                    },
                  );
                }),
              ],
            ),
    );
  }
}
