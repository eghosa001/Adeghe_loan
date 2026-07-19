import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class SecureStorageService {
  final _storage = const FlutterSecureStorage();

  static const _pinKey = 'auth_pin_hash';
  static const _recoveryPassKey = 'recovery_pass_hash';
  static const _biometricKey = 'biometric_enabled';
  static const _dbKey = 'db_encryption_key';
  static const _fileEncryptionKey = 'file_encryption_key';

  String _hash(String data) {
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString();
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: _hash(pin));
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;
    return storedHash == _hash(pin);
  }

  Future<bool> hasPin() async {
    final storedHash = await _storage.read(key: _pinKey);
    return storedHash != null;
  }

  Future<void> saveRecoveryPassword(String password) async {
    await _storage.write(key: _recoveryPassKey, value: _hash(password));
  }

  Future<bool> verifyRecoveryPassword(String password) async {
    final storedHash = await _storage.read(key: _recoveryPassKey);
    if (storedHash == null) return false;
    return storedHash == _hash(password);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled.toString());
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricKey);
    return value == 'true';
  }

  Future<String> getDatabaseKey() async {
    String? key = await _storage.read(key: _dbKey);
    if (key == null) {
      key = const Uuid().v4();
      await _storage.write(key: _dbKey, value: key);
    }
    return key;
  }

  /// Returns a device-local secret used exclusively for encrypted documents.
  /// The secret itself never enters the SQLite database or regular storage.
  Future<String> getFileEncryptionKey() async {
    String? key = await _storage.read(key: _fileEncryptionKey);
    if (key == null) {
      key = const Uuid().v4();
      await _storage.write(key: _fileEncryptionKey, value: key);
    }
    return key;
  }
}
