import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import '../../data/services/p2p_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController(text: 'Peer_${DateTime.now().millisecond}');
  final _bootstrapController = TextEditingController(text: '192.168.1.18:8888');
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
  }

  void _handleLogin() async {
    setState(() => _loading = true);
    final p2p = Provider.of<P2PService>(context, listen: false);

    final parts = _bootstrapController.text.split(':');
    final ip = parts[0];
    final port = int.tryParse(parts[1]) ?? 8888;

    try {
      await p2p.init(_nameController.text, ip, port);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/icons/ic_logo.png', width: 80, height: 80),
              const SizedBox(height: 16),
              const Text(
                'PeerBuzz',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bootstrapController,
                decoration: const InputDecoration(
                  labelText: 'Bootstrap Server Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 236, 97, 23),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loading ? null : _handleLogin,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text(
                          'Tham gia mạng',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
