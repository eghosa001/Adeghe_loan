import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/security/biometric_service.dart';
import '../../../../core/widgets/keyboard_scrollable.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  bool _biometricEnabled = false;
  final _storage = SecureStorageService();
  final _bio = BiometricService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _biometricEnabled = await _storage.isBiometricEnabled();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleBiometric(bool val) async {
    if (val) {
      final available = await _bio.isBiometricAvailable();
      if (!available) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Biometric not available on this device')));
        return;
      }
      // A successful scan is required BEFORE enabling (documented lock-in):
      // enabling must never be possible without proving the enrolled biometric
      // actually works, otherwise a broken/absent enrolment silently "enables"
      // a feature that can never unlock the app.
      final result = await _bio.authenticate();
      if (!mounted) return;
      if (result != BiometricResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Authentication failed. Biometrics not enabled.')));
        return;
      }
    }
    await _storage.setBiometricEnabled(val);
    if (!mounted) return;
    setState(() => _biometricEnabled = val);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security Settings')),
      body: KeyboardScrollable(
        child: ListView(padding: const EdgeInsets.all(8.0), children: [
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Fingerprint Unlock'),
            trailing:
                Switch(value: _biometricEnabled, onChanged: _toggleBiometric),
          ),
          ListTile(
            leading: const Icon(Icons.pin),
            title: const Text('Change PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/auth/change_pin'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Forgot PIN / Reset'),
            onTap: () => context.push('/auth/forgot_pin'),
          ),
        ]),
      ),
    );
  }
}
