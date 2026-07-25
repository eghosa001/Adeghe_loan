import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../providers/auth_provider.dart';

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _pin = '';
  String _confirm = '';
  bool _isConfirming = false;
  final _storage = SecureStorageService();
  final _recoveryCtrl = TextEditingController();

  void _onKey(String key) {
    setState(() {
      if (!_isConfirming) {
        if (_pin.length < 4) _pin += key;
        if (_pin.length == 4) _isConfirming = true;
      } else {
        if (_confirm.length < 4) _confirm += key;
      }
    });

    if (_isConfirming && _confirm.length == _pin.length && _pin.isNotEmpty) {
      if (_pin == _confirm) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Set Recovery Password'),
            content: TextField(
              controller: _recoveryCtrl,
              decoration: const InputDecoration(labelText: 'Recovery Password'),
              obscureText: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final recovery = _recoveryCtrl.text.trim();
                  if (recovery.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please enter a recovery password')));
                    return;
                  }
                  Navigator.of(ctx).pop();
                  _savePinWithRecovery(recovery);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      } else {
        _showMismatch();
      }
    }
  }

  void _showMismatch() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('PINs do not match')));
    setState(() {
      _pin = '';
      _confirm = '';
      _isConfirming = false;
    });
  }

  Future<void> _savePinWithRecovery(String recovery) async {
    await _storage.saveRecoveryPassword(recovery);
    await _storage.savePin(_pin);
    ref.read(authProvider.notifier).unlock();
    if (mounted) GoRouter.of(context).go('/dashboard');
  }

  @override
  void dispose() {
    _recoveryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = _isConfirming ? 'Confirm PIN' : 'Set a PIN';
    return Scaffold(
      appBar: AppBar(title: Text(display)),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(display, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            _buildPinDots(),
            const SizedBox(height: 24),
            _buildNumpad(),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    final length = _isConfirming ? _confirm.length : _pin.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
          4,
          (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < length
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                ),
              )),
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
