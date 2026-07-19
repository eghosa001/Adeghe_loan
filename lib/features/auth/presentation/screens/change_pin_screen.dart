import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/security/secure_storage_service.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});
  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _storage = SecureStorageService();
  final _current = TextEditingController();
  final _new = TextEditingController();
  String _msg = '';

  Future<void> _change() async {
    final valid = await _storage.verifyPin(_current.text);
    if (!valid) {
      setState(() => _msg = 'Current PIN incorrect');
      return;
    }
    await _storage.savePin(_new.text);
    if (mounted) GoRouter.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(
              controller: _current,
              decoration: const InputDecoration(labelText: 'Current PIN'),
              obscureText: true),
          const SizedBox(height: 12),
          TextField(
              controller: _new,
              decoration: const InputDecoration(labelText: 'New PIN'),
              obscureText: true),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _change, child: const Text('Change PIN')),
          if (_msg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(_msg, style: const TextStyle(color: Colors.red))),
        ]),
      ),
    );
  }
}
