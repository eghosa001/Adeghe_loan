import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Result of a biometric authentication attempt.
enum BiometricResult {
  /// Authentication succeeded.
  success,

  /// Authentication failed (wrong fingerprint/face).
  failed,

  /// Biometric hardware is unavailable or not enrolled.
  unavailable,

  /// An error occurred (e.g. system dialog cancelled, hardware failure).
  error,
}

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
    final canAuthenticate =
        canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
    return canAuthenticate;
  }

  /// Authenticates the user via biometrics.
  ///
  /// Returns [BiometricResult.success] on success, [BiometricResult.failed]
  /// when the biometric check fails (wrong fingerprint/face),
  /// [BiometricResult.unavailable] when no biometric hardware is enrolled,
  /// or [BiometricResult.error] for other failures (e.g. system dialog
  /// cancelled, hardware error).
  Future<BiometricResult> authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason:
            'Scan your fingerprint (or face) to unlock the application',
        biometricOnly: true,
        // Do not keep the biometric grant alive across app backgrounding: the
        // app re-locks when paused, so the grant must not outlive it.
        persistAcrossBackgrounding: false,
      );
      return authenticated ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      // PlatformException.code values:
      //   'Lockout'        — too many attempts, biometric temporarily disabled
      //   'BiometricError' — hardware error or not enrolled
      //   'BiometricNotFound' — no biometric data enrolled
      //   'BiometricNotAvailable' — hardware not available
      if (e.code == 'BiometricNotFound' ||
          e.code == 'BiometricNotAvailable' ||
          e.code == 'BiometricError') {
        return BiometricResult.unavailable;
      }
      // 'Lockout' and other platform errors are treated as unavailable so the
      // caller falls back to PIN.
      return BiometricResult.unavailable;
    } catch (_) {
      return BiometricResult.error;
    }
  }
}
