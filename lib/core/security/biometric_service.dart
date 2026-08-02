import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isBiometricAvailable() async {
    final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
    final canAuthenticate =
        canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
    return canAuthenticate;
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason:
            'Scan your fingerprint (or face) to unlock the application',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      return false;
    }
  }
}
