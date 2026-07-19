import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/security/secure_storage_service.dart';

class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});
  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _storage = SecureStorageService();
  final _controller = TextEditingController();
  String _message = '';

  Future<void> _verifyRecovery() async {
    final ok = await _storage.verifyRecoveryPassword(_controller.text);
    if (ok) {
      if (mounted) GoRouter.of(context).go('/auth/setup_pin');
    } else {
      setState(() => _message = 'Recovery password incorrect');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot PIN')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Enter your recovery password to reset PIN'),
            const SizedBox(height: 12),
            TextField(
                controller: _controller,
                decoration:
                    const InputDecoration(labelText: 'Recovery Password')),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _verifyRecovery, child: const Text('Verify')),
            if (_message.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(_message,
                      style: const TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}
