import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/security/biometric_service.dart';
import '../providers/auth_provider.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});
  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  String _pin = '';
  final _storage = SecureStorageService();
  final _bio = BiometricService();
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final enabled = await _storage.isBiometricEnabled();
    if (enabled) {
      final success = await _bio.authenticate();
      if (success) _unlockApp();
    }
  }

  void _unlockApp() {
    ref.read(authProvider.notifier).unlock();
    GoRouter.of(context).go('/dashboard');
  }

  void _onKey(String key) async {
    if (_pin.length < 4) {
      setState(() {
        _pin += key;
        _isError = false;
      });
      if (_pin.length == 4) {
        final isValid = await _storage.verifyPin(_pin);
        if (isValid) {
          _unlockApp();
        } else {
          setState(() {
            _isError = true;
            _pin = '';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter PIN')),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'attached_assets/full_horizontal_logo_1784971585520.png',
              width: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            Text('Enter PIN', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  4,
                  (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < _pin.length
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300,
                        ),
                      )),
            ),
            if (_isError)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text('Incorrect PIN',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 24),
            _buildNumpad(),
            TextButton(
                onPressed: () => context.push('/auth/forgot_pin'),
                child: const Text('Forgot PIN?')),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: keys
          .map(
              (k) => ElevatedButton(onPressed: () => _onKey(k), child: Text(k)))
          .toList(),
    );
  }
}
