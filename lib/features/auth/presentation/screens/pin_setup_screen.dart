import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_numpad.dart';
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
    HapticFeedback.lightImpact();
    setState(() {
      if (!_isConfirming) {
        if (_pin.length < AppConstants.maxPinLength) _pin += key;
        if (_pin.length == AppConstants.pinLength) _isConfirming = true;
      } else {
        if (_confirm.length < AppConstants.maxPinLength) _confirm += key;
      }
    });

    if (_isConfirming && _confirm.length == _pin.length && _pin.isNotEmpty) {
      if (_pin == _confirm) {
        _showRecoveryDialog();
      } else {
        _showMismatch();
      }
    }
  }

  void _onDelete() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_isConfirming && _confirm.isNotEmpty) {
        _confirm = _confirm.substring(0, _confirm.length - 1);
      } else if (!_isConfirming && _pin.isNotEmpty) {
        _pin = _pin.substring(0, _pin.length - 1);
      }
    });
  }

  /// Physical-keyboard entry (desktop: there is no touch numpad). Digits
  /// (top row or numpad) append to the current PIN field, Backspace deletes.
  /// Only handles [KeyDownEvent] so each press registers once.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 0x30 &&
        character.codeUnitAt(0) <= 0x39) {
      _onKey(character);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _onDelete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showRecoveryDialog() {
    showDialog(
      context: context,
      // The dialog has real side effects (it clears a half-entered PIN on
      // dismiss); letting a tap outside or a back press silently dismiss it
      // leaves a confusing mid-confirm state, so both are intercepted and run
      // the same cancellation path as the Cancel button.
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _cancelRecoverySetup(ctx);
        },
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Set Recovery Password',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _recoveryCtrl,
                decoration: const InputDecoration(labelText: 'Recovery Password'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'At least 16 characters, with letters and numbers. '
                'It is the only way to recover if you forget your PIN.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _cancelRecoverySetup(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final recovery = _recoveryCtrl.text.trim();
                final error = SecureStorageService.recoveryPasswordError(recovery);
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error)),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                _savePinWithRecovery(recovery);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared cancellation path for the recovery dialog's Cancel button and for
  /// a system back press (PopScope) — clears the half-entered PIN/confirm so
  /// the screen does not stay stuck in "Confirm your PIN".
  void _cancelRecoverySetup(BuildContext dialogContext) {
    Navigator.of(dialogContext).pop();
    _recoveryCtrl.clear();
    setState(() {
      _pin = '';
      _confirm = '';
      _isConfirming = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('PIN setup cancelled. Try again when ready.')),
    );
  }

  void _showMismatch() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PINs do not match. Please try again.')),
    );
    setState(() {
      _pin = '';
      _confirm = '';
      _isConfirming = false;
    });
  }

  Future<void> _savePinWithRecovery(String recovery) async {
    try {
      await _storage.savePin(_pin);
      await _storage.saveRecoveryPassword(recovery);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
      return;
    }
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
    final display = _isConfirming ? 'Confirm your PIN' : 'Create a PIN';
    final currentLength = _isConfirming ? _confirm.length : _pin.length;

    return Scaffold(
      body: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColor, Color(0xFF0D2B3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.accentGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentColor.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'A',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                display,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConfirming
                    ? 'Re-enter your ${AppConstants.pinLength}-digit PIN'
                    : 'Choose a ${AppConstants.pinLength}-digit PIN to secure your app',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 32),
              _buildPinDots(currentLength),
              const Spacer(flex: 1),
              AppNumpad(
                onKeyPressed: _onKey,
                onDelete: _onDelete,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildPinDots(int length) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(AppConstants.pinLength, (i) {
        final filled = i < length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: filled ? 18 : 14,
          height: filled ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? AppTheme.accentColor
                : Colors.white.withValues(alpha: 0.2),
            border: Border.all(
              color: filled
                  ? AppTheme.accentColor
                  : Colors.white.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: AppTheme.accentColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
