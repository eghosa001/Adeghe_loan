import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// Windows/Linux/macOS: `local_auth` desktop implementations do not support
  /// the `biometricOnly` option (local_auth_windows throws `UnsupportedError`
  /// for it), and on some of them enrollment reporting is unreliable. They
  /// rely on the OS dialog (Windows Hello / OS keychain) to pick the
  /// available method, so enrollment is not required here.
  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<bool> isBiometricAvailable() async {
    final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
    final canAuthenticate =
        canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
    if (!canAuthenticate) return false;
    if (_isDesktop) return true;
    // `canCheckBiometrics`/`isDeviceSupported` only report that the hardware
    // and API exist — on some platforms they return true even when NO
    // fingerprint or face is enrolled. Confirm actual enrollment where the
    // plugin exposes it so a not-enrolled device reports as unavailable
    // instead of surfacing a confusing "verification failed" dialog.
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return false;
    } catch (_) {
      // Platform does not expose enrollment (e.g. some desktop builds);
      // fall back to the hardware/API check above.
    }
    return true;
  }

  /// Authenticates the user via biometrics.
  ///
  /// Returns [BiometricResult.success] on success, [BiometricResult.failed]
  /// when the biometric check fails (wrong fingerprint/face),
  /// [BiometricResult.unavailable] when no biometric hardware is enrolled,
  /// or [BiometricResult.error] for other failures (e.g. system dialog
  /// cancelled, hardware error).
  Future<BiometricResult> authenticate() async {
    // Guard up-front: with no biometrics enrolled the platform dialog reports
    // a generic failure/cancel. Returning `unavailable` here lets callers show
    // the correct "not enabled / not enrolled" message instead of a misleading
    // "biometric verification failed".
    if (!await isBiometricAvailable()) return BiometricResult.unavailable;
    try {
      final authenticated = await _auth.authenticate(
        localizedReason:
            'Scan your fingerprint (or face) to unlock the application',
        // Desktop implementations (notably local_auth_windows) throw for
        // `biometricOnly: true`, which is why the prompt silently never
        // appeared on PC. The OS dialog (Windows Hello) already presents the
        // available method — fingerprint, face or PIN — so biometricOnly is
        // only enforced on mobile where the fingerprint-only prompt is the
        // expected behaviour.
        biometricOnly: !_isDesktop,
        // Do not keep the biometric grant alive across app backgrounding: the
        // app re-locks when paused, so the grant must not outlive it.
        persistAcrossBackgrounding: false,
      );
      return authenticated ? BiometricResult.success : BiometricResult.failed;
    } on LocalAuthException catch (e) {
      // local_auth 3.x surfaces failures via LocalAuthException (e.g. no
      // biometrics enrolled, hardware temporarily unavailable, lockout, or the
      // user cancelling the OS dialog). All of these are recoverable by falling
      // back to the PIN pad, so they map to `unavailable`/`error` — never a
      // crash.
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.userRequestedFallback:
          return BiometricResult.error;
        default:
          // noBiometricsEnrolled / noBiometricHardware /
          // biometricHardwareTemporarilyUnavailable / temporaryLockout /
          // biometricLockout / noCredentialsSet / deviceError / unknownError …
          return BiometricResult.unavailable;
      }
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
