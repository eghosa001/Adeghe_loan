import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data' show BytesBuilder, Uint8List;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'secure_key_value_store.dart';

class SecureStorageService implements SecureKeyValueStore {
  final _storage = const FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'AdegheSecureStorage',
      publicKey: 'AdegheSecureStoragePublicKey',
    ),
  );

  static const _pinKey = 'auth_pin_hash';
  static const _recoveryPassKey = 'recovery_pass_hash';
  static const _biometricKey = 'biometric_enabled';
  static const _dbKey = 'db_encryption_key';
  static const _fileEncryptionKey = 'file_encryption_key';
  static const _pinVersionKey = 'pin_digit_version';
  static const _currentPinVersion = '4';

  // PBKDF2-HMAC-SHA256 iterations — high enough to slow brute force while
  // staying instant on a phone.
  static const _pinIterations = 120000;
  static const _pinHashLength = 32;

  /// Returns the per-device random salt used for all PIN/recovery hashes.
  /// Stored once in secure storage so hashes stay stable across writes.
  Future<String> _getSalt() async {
    String? salt = await _storage.read(key: AppConstants.keyPinSalt);
    if (salt == null) {
      final random = Random.secure();
      salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
      await _storage.write(key: AppConstants.keyPinSalt, value: salt);
    }
    return salt;
  }

  static String _pbkdf2Hex(String data, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(data));
    final blockIndex = Uint8List(4);
    final out = BytesBuilder();
    var block = 1;
    while (out.length < _pinHashLength) {
      blockIndex[0] = (block >> 24) & 0xff;
      blockIndex[1] = (block >> 16) & 0xff;
      blockIndex[2] = (block >> 8) & 0xff;
      blockIndex[3] = block & 0xff;
      final start = <int>[...utf8.encode(salt), ...blockIndex];
      var u = hmac.convert(start).bytes;
      var t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < u.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    final bytes = out.toBytes();
    return base64Encode(bytes.sublist(0, _pinHashLength));
  }

  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  /// PBKDF2-HMAC-SHA256 with the stored random salt. Format:
  /// `pbkdf2-sha256:<iterations>:<digest hex>`.
  Future<String> _hash(String data) async {
    final salt = await _getSalt();
    return 'pbkdf2-sha256:$_pinIterations:${_pbkdf2Hex(data, salt, _pinIterations)}';
  }

  Future<bool> _verify(String data, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 3 || parts[0] != 'pbkdf2-sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1000) return false;
    final salt = await _getSalt();
    final expected = _pbkdf2Hex(data, salt, iterations);
    return _constantTimeEquals(expected, parts[2]);
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: await _hash(pin));
    await _storage.write(key: _pinVersionKey, value: _currentPinVersion);
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _pinVersionKey);
  }

  /// Returns true if the stored PIN was set with the current 4-digit scheme.
  /// Returns false for old PINs or when no version marker exists.
  Future<bool> isPinVersionCurrent() async {
    final version = await _storage.read(key: _pinVersionKey);
    return version == _currentPinVersion;
  }

  /// Call at app start: if an old-format PIN exists (no version marker),
  /// clears it so the user is directed to re-set a 4-digit PIN.
  Future<void> migrateToFourDigitPin() async {
    final hasExistingPin = await hasPin();
    if (hasExistingPin) {
      final isCurrent = await isPinVersionCurrent();
      if (!isCurrent) {
        await clearPin();
      }
    }
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;
    return _verify(pin, storedHash);
  }

  Future<bool> hasPin() async {
    final storedHash = await _storage.read(key: _pinKey);
    return storedHash != null;
  }

  Future<void> saveRecoveryPassword(String password) async {
    await _storage.write(key: _recoveryPassKey, value: await _hash(password));
  }

  Future<bool> verifyRecoveryPassword(String password) async {
    final storedHash = await _storage.read(key: _recoveryPassKey);
    if (storedHash == null) return false;
    return _verify(password, storedHash);
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
