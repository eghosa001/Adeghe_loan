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
  bool _isPermanentlyLocked = false;
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
    if (await _lockout?.isPermanentlyLocked() ?? false) {
      if (!mounted) return;
      setState(() => _isPermanentlyLocked = true);
      return;
    }
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

  /// Under a permanent lock the PIN input stays blocked, but the recovery
  /// password field must stay usable — it is the only way back in.
  bool get _blocked => _isLockedOut && !_isPermanentlyLocked;

  int get _remainingSeconds {
    if (_lockoutUntil == null) return 0;
    return _lockoutUntil!.difference(DateTime.now()).inSeconds.clamp(0, 999);
  }

  Future<void> _verifyRecovery() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _message = 'Please enter your recovery password');
      return;
    }

    if (_blocked) {
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
      if (_isPermanentlyLocked) {
        setState(() => _message = 'Recovery password incorrect.');
        return;
      }
      final triggered = await _lockout?.registerFailedAttempt() ?? false;
      if (!mounted) return;
      if (triggered) {
        final permanent = await _lockout?.isPermanentlyLocked() ?? false;
        if (!mounted) return;
        if (permanent) {
          setState(() {
            _isPermanentlyLocked = true;
            _lockoutUntil = null;
            _lockoutTimer?.cancel();
            _message = 'Too many failed attempts. This device is locked. '
                'Enter your recovery password to reset your PIN.';
          });
          return;
        }
        final remaining = await _lockout?.remainingLockout();
        if (!mounted) return;
        setState(() {
          _lockoutUntil =
              DateTime.now().add(remaining ?? _lockout!.lockoutDuration);
          _message = 'Too many failed attempts. Locked out for '
              '${_lockoutUntil!.difference(DateTime.now()).inMinutes + 1} minutes.';
          _startLockoutTimer();
        });
      } else {
        final attemptsLeft = await _lockout?.remainingAttempts() ?? 0;
        if (!mounted) return;
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
    final isLocked = _blocked;

    return Scaffold(
      appBar: AppBar(title: const Text('Forgot PIN')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(_isPermanentlyLocked
                ? 'Too many failed attempts. This device is locked. Enter '
                    'your recovery password to reset your PIN.'
                : 'Enter your recovery password to reset PIN'),
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
