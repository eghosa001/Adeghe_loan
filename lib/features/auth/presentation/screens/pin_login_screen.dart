import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/security/secure_storage_service.dart';
import '../../../../core/security/biometric_service.dart';
import '../../../../core/security/pin_lockout_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_numpad.dart';
import '../providers/auth_provider.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});
  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  final _storage = SecureStorageService();
  final _bio = BiometricService();
  bool _isError = false;
  bool _isPermanentlyLocked = false;
  String? _lockoutMessage;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticOut),
    );
    // The biometric prompt must not fire while a route transition (splash ->
    // PIN, or re-entering after an inactivity/background lock) is still
    // settling: Android drops the BiometricPrompt when it is triggered on a
    // not-yet-resumed Activity, which is exactly why the prompt appeared to
    // never show. Defer until the first frame and the transition have
    // completed, then check.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), _checkBiometrics);
    });
    _checkLockout();
  }

  Future<void> _checkLockout() async {
    final lockout = PinLockoutService(_storage);
    if (await lockout.isPermanentlyLocked()) {
      if (!mounted) return;
      setState(() {
        _isPermanentlyLocked = true;
        _lockoutMessage = 'Too many failed attempts. This device is locked. '
            'Use "Forgot PIN" and your recovery password to reset it.';
      });
      return;
    }
    final message = await _lockoutCountdown(lockout);
    if (!mounted || message == null) return;
    setState(() => _lockoutMessage = message);
  }

  /// Formats the ACTUAL remaining lockout (which escalates per cycle: 5, 10,
  /// 20, 40 min …) instead of a hard-coded base duration. Returns null when
  /// not locked out.
  Future<String?> _lockoutCountdown(PinLockoutService lockout) async {
    final remaining = await lockout.remainingLockout();
    if (remaining == null) return null;
    final minutes = remaining.inMinutes;
    if (minutes > 0) return 'Too many attempts. Try again in $minutes min.';
    final seconds = remaining.inSeconds.clamp(1, 59);
    return 'Too many attempts. Try again in $seconds sec.';
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final enabled = await _storage.isBiometricEnabled();
    if (!enabled || !mounted) return;
    // A permanent lock can only be cleared by the recovery password; never let
    // biometrics bypass it.
    if (await PinLockoutService(_storage).isPermanentlyLocked()) return;
    // Retry a few times before giving up: at launch the platform can report
    // biometrics transiently unavailable (enrollment/API not yet settled), and
    // a silent `unavailable` must not swallow the prompt the user enabled.
    for (var attempt = 0; attempt < 3 && mounted; attempt++) {
      final result = await _bio.authenticate();
      if (!mounted) return;
      if (result == BiometricResult.success) {
        _unlockApp();
        return;
      }
      // `failed` means the user actively dismissed a wrong scan — do not nag.
      if (result == BiometricResult.failed) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  void _unlockApp() {
    try {
      ref.read(authProvider.notifier).unlock();
      GoRouter.of(context).go('/dashboard');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to unlock. Please try again.')),
        );
      }
    }
  }

  Future<void> _onKey(String key) async {
    try {
      if (_isPermanentlyLocked) return;
      if (_pin.length < AppConstants.maxPinLength) {
        HapticFeedback.lightImpact();
        setState(() {
          _pin += key;
          _isError = false;
          _lockoutMessage = null;
        });
        if (_pin.length == AppConstants.pinLength) {
          final pinToVerify = _pin;
          await Future.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;

          final lockout = PinLockoutService(_storage);
          final lockedOut = await lockout.isLockedOut();
          if (!mounted) return;
          if (lockedOut) {
            HapticFeedback.heavyImpact();
            _shakeController.forward(from: 0);
            final countdown = await _lockoutCountdown(lockout);
            if (!mounted) return;
            setState(() {
              _isError = true;
              _lockoutMessage = countdown;
              _pin = '';
            });
            return;
          }

          final isValid = await _storage.verifyPin(pinToVerify);
          if (!mounted) return;
          if (isValid) {
            await lockout.reset();
            HapticFeedback.heavyImpact();
            _unlockApp();
          } else {
            final triggeredLockout = await lockout.registerFailedAttempt();
            if (!mounted) return;
            final permanent = await lockout.isPermanentlyLocked();
            if (!mounted) return;
            HapticFeedback.heavyImpact();
            _shakeController.forward(from: 0);
            String? lockoutMessage;
            if (permanent) {
              lockoutMessage = 'Too many failed attempts. This device is '
                  'locked. Use "Forgot PIN" and your recovery password to '
                  'reset it.';
            } else {
              lockoutMessage = triggeredLockout
                  ? await _lockoutCountdown(lockout)
                  : 'Incorrect PIN. Try again.';
            }
            if (!mounted) return;
            setState(() {
              _isError = true;
              _isPermanentlyLocked = permanent;
              _lockoutMessage = lockoutMessage;
              _pin = '';
            });
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isError = true;
        _lockoutMessage = 'An error occurred. Please try again.';
        _pin = '';
      });
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _isError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
              _buildLogo(),
              const SizedBox(height: 12),
              Text(
                'Adeghe Professional Services',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Created by AIGHEWI EGHOSA',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFD4A847),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter your PIN to continue',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(flex: 1),
              _buildPinDots(),
              if (_isError)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: AnimatedBuilder(
                    animation: _shakeAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          sin(_shakeAnimation.value * pi * 3) * 8,
                          0,
                        ),
                        child: child,
                      );
                    },
                    child: Text(
                      _lockoutMessage ?? 'Incorrect PIN. Try again.',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              const Spacer(flex: 1),
              AppNumpad(
                onKeyPressed: _onKey,
                onDelete: _onDelete,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.push('/auth/forgot_pin'),
                child: Text(
                  'Forgot PIN?',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 80,
      height: 80,
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
            fontSize: 36,
            fontWeight: FontWeight.w800,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(AppConstants.pinLength, (i) {
            final filled = i < _pin.length;
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
      },
    );
  }

}
