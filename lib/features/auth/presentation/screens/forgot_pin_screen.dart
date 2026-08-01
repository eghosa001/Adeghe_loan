import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/security/pin_lockout_service.dart';

class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});
  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _storage = SecureStorageService();
  final _controller = TextEditingController();
  String _message = '';
  bool _isLoading = false;

  PinLockoutService? _lockout;
  DateTime? _lockoutUntil;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _lockout = PinLockoutService(_storage);
    _refreshLockout();
  }

  @override
  void dispose() {
    _controller.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final until = await _lockout?.remainingLockout();
    if (!mounted) return;
    if (until != null) {
      setState(() {
        _lockoutUntil = DateTime.now().add(until);
        _startLockoutTimer();
      });
    }
  }

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isBefore(_lockoutUntil!)) return true;
    _lockoutUntil = null;
    return false;
  }

  int get _remainingSeconds {
    if (_lockoutUntil == null) return 0;
    return _lockoutUntil!.difference(DateTime.now()).inSeconds.clamp(0, 999);
  }

  Future<void> _verifyRecovery() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _message = 'Please enter your recovery password');
      return;
    }

    if (_isLockedOut) {
      setState(() =>
          _message = 'Too many attempts. Try again in $_remainingSeconds seconds.');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = '';
    });
    final ok = await _storage.verifyRecoveryPassword(_controller.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (ok) {
      await _lockout?.reset();
      if (!mounted) return;
      GoRouter.of(context).go('/auth/setup_pin');
    } else {
      final triggered = await _lockout?.registerFailedAttempt() ?? false;
      if (!mounted) return;
      if (triggered) {
        setState(() {
          _lockoutUntil = DateTime.now().add(_lockout!.lockoutDuration);
          _message = 'Too many failed attempts. Locked out for '
              '${_lockout!.lockoutDuration.inMinutes} minutes.';
          _startLockoutTimer();
        });
      } else {
        final attemptsLeft = _lockout!.maxAttempts;
        setState(() => _message =
            'Recovery password incorrect. $attemptsLeft attempts remaining.');
      }
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _lockoutTimer?.cancel();
        return;
      }
      setState(() {
        if (!_isLockedOut) {
          _lockoutTimer?.cancel();
          _message = '';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _isLockedOut;

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
                obscureText: true,
                enabled: !isLocked,
                decoration:
                    const InputDecoration(labelText: 'Recovery Password')),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: (_isLoading || isLocked) ? null : _verifyRecovery,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : isLocked
                        ? Text('Locked ($_remainingSeconds s)')
                        : const Text('Verify')),
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
