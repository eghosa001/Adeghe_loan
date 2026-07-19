import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../../../core/security/secure_storage_service.dart';

class AuthRepository {
  AuthRepository(this._ref);
  final Ref _ref;

  SecureStorageService get _storage => _ref.read(secureStorageProvider);

  Future<bool> hasPin() => _storage.hasPin();

  Future<void> savePin(String pin) => _storage.savePin(pin);

  Future<bool> verifyPin(String pin) => _storage.verifyPin(pin);

  Future<void> saveRecoveryPassword(String password) =>
      _storage.saveRecoveryPassword(password);

  Future<bool> verifyRecoveryPassword(String password) =>
      _storage.verifyRecoveryPassword(password);

  Future<bool> isBiometricEnabled() => _storage.isBiometricEnabled();

  Future<void> setBiometricEnabled(bool enabled) =>
      _storage.setBiometricEnabled(enabled);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref);
});
