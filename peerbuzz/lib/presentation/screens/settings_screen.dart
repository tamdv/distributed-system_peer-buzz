import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/services/p2p_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p2p = Provider.of<P2PService>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình Peer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoTile('Tên hiển thị', p2p.localPeer.name, Icons.person),
          _buildInfoTile('Peer ID', p2p.localPeer.id, Icons.fingerprint),
          _buildInfoTile('Địa chỉ IP', p2p.localPeer.ip, Icons.lan),
          _buildInfoTile(
              'Cổng', p2p.localPeer.port.toString(), Icons.door_front_door),
          const Divider(height: 40),
          const Text(
            'Trạng thái hệ thống',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Lamport Clock Value'),
            trailing: Text(
              p2p.clock.value.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Peers Online'),
            trailing: Text(
              p2p.onlinePeers.length.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await p2p.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Đăng xuất & Thoát mạng'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
