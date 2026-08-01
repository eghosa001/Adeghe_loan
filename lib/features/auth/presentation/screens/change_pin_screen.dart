import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/security/pin_lockout_service.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});
  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  final _storage = SecureStorageService();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String _msg = '';

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    final newPin = _new.text.trim();
    final confirmPin = _confirm.text.trim();

    if (newPin.length != AppConstants.pinLength ||
        confirmPin.length != AppConstants.pinLength) {
      setState(() =>
          _msg = 'PIN must be exactly ${AppConstants.pinLength} digits');
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(newPin)) {
      setState(() => _msg = 'PIN must contain only digits');
      return;
    }
    if (newPin != confirmPin) {
      setState(() => _msg = 'PINs do not match');
      return;
    }
    final valid = await _storage.verifyPin(_current.text);
    if (!mounted) return;
    if (!valid) {
      final lockout = PinLockoutService(_storage);
      final triggered = await lockout.registerFailedAttempt();
      if (!mounted) return;
      setState(() => _msg = triggered
          ? 'Too many failed attempts. Try again in '
              '${lockout.lockoutDuration.inMinutes} min.'
          : 'Current PIN incorrect');
      return;
    }
    await PinLockoutService(_storage).reset();
    await _storage.savePin(newPin);
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
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: AppConstants.maxPinLength),
          const SizedBox(height: 12),
          TextField(
              controller: _new,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: AppConstants.maxPinLength),
          const SizedBox(height: 12),
          TextField(
              controller: _confirm,
              decoration: const InputDecoration(
                labelText: 'Confirm New PIN',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: AppConstants.maxPinLength),
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
