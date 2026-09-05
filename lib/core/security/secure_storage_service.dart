import 'dart:convert';
import 'dart:isolate';
import 'dart:math' show Random;
import 'dart:typed_data' show BytesBuilder, Uint8List;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'secure_key_value_store.dart';

class SecureStorageService implements SecureKeyValueStore {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage(
    webOptions: WebOptions(
      dbName: 'AdegheSecureStorage',
      publicKey: 'AdegheSecureStoragePublicKey',
    ),
  );

  static const _pinKey = AppConstants.keyPinHash;
  static const _recoveryPassKey = 'recovery_pass_hash';
  static const _biometricKey = 'biometric_enabled';
  static const _dbKey = 'db_encryption_key';
  static const _fileEncryptionKey = 'file_encryption_key';
  static const _docKeysKey = 'doc_derived_keys';
  static const _pinVersionKey = 'pin_digit_version';
  static const _currentPinVersion = '4';
  static const _pinIterations = 120000;
  static const _recoveryIterations = 600000;
  static const _pinHashLength = 32;
  static const String docDerivationSalt = 'loantrack-doc-key-v1';
  static const int _docDerivedIterations = 600000;
  static const int _maxDocKeys = 5;
  static const String backupDerivationDomain = 'adeghe-backup-v2';

  Future<String> _getSalt(String key) async {
    String? salt = await _storage.read(key: key);
    if (salt == null) {
      final random = Random.secure();
      salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
      await _storage.write(key: key, value: salt);
    }
    return salt;
  }

  Future<String?> _readSalt(String key) => _storage.read(key: key);

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

  static Future<String> _pbkdf2HexAsync(String data, String salt, int iterations) =>
      Isolate.run(() => _pbkdf2Hex(data, salt, iterations));

  static bool _constantTimeEquals(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    var diff = 0;
    for (var i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
    return diff == 0;
  }

  Future<String> _hash(String data, String saltKey, int iterations) async {
    final salt = await _getSalt(saltKey);
    final digest = await _pbkdf2HexAsync(data, salt, iterations);
    return 'pbkdf2-sha256:$iterations:$digest';
  }

  Future<bool> _verify(String data, String stored, List<String> saltCandidates) async {
    final parts = stored.split(':');
    if (parts.length != 3 || parts[0] != 'pbkdf2-sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1000) return false;
    for (final salt in saltCandidates) {
      if (salt.isEmpty) continue;
      final expected = await _pbkdf2HexAsync(data, salt, iterations);
      if (_constantTimeEquals(expected, parts[2])) return true;
    }
    return false;
  }

  static String? recoveryPasswordError(String password) {
    if (password.length < 16) return 'Recovery password must be at least 16 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) || !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Recovery password must contain both letters and numbers';
    }
    return null;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: await _hash(pin, AppConstants.keyPinSalt, _pinIterations));
    await _storage.write(key: _pinVersionKey, value: _currentPinVersion);
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);

  Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _pinVersionKey);
  }

  Future<bool> isPinVersionCurrent() async => await _storage.read(key: _pinVersionKey) == _currentPinVersion;

  Future<void> migrateToFourDigitPin() async {
    if (await hasPin() && !await isPinVersionCurrent()) await clearPin();
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;
    return _verify(pin, storedHash, [(await _readSalt(AppConstants.keyPinSalt)) ?? '']);
  }

  Future<bool> hasPin() async => await _storage.read(key: _pinKey) != null;

  Future<void> saveRecoveryPassword(String password) async {
    await _storage.write(
      key: _recoveryPassKey,
      value: await _hash(password, AppConstants.keyRecoverySalt, _recoveryIterations),
    );
    await _storeDerivedDocKey(password);
  }

  Future<void> _storeDerivedDocKey(String password) async {
    final derived = await _pbkdf2HexAsync(password, docDerivationSalt, _docDerivedIterations);
    final existing = await _storage.read(key: _docKeysKey);
    List<String> keys;
    try {
      keys = [derived, ...(jsonDecode(existing ?? '[]') as List).whereType<String>().where((k) => k != derived)];
    } catch (_) {
      keys = [derived];
    }
    await _storage.write(key: _docKeysKey, value: jsonEncode(keys.take(_maxDocKeys).toList()));
  }

  static String deriveDocumentKey(String password, {int iterations = 600000}) =>
      _pbkdf2Hex(password, docDerivationSalt, iterations);

  /// Derives the LTBK2 backup key from the recovery secret and a random
  /// per-backup salt. The recovery password itself is never stored in a backup.
  static String deriveBackupKey(String password, {required List<int> salt, int iterations = 600000}) {
    final master = base64Decode(_pbkdf2Hex(password, docDerivationSalt, iterations));
    final material = <int>[...utf8.encode(backupDerivationDomain), ...salt];
    return base64UrlEncode(Uint8List.fromList(Hmac(sha256, master).convert(material).bytes));
  }

  /// Same derivation as [deriveBackupKey], but starts from the cached recovery
  /// derived key so automatic backups never need the plaintext password.
  static String deriveBackupKeyFromDerivedKey(String derivedKey, {required List<int> salt}) {
    final master = base64Decode(derivedKey);
    final material = <int>[...utf8.encode(backupDerivationDomain), ...salt];
    return base64UrlEncode(Uint8List.fromList(Hmac(sha256, master).convert(material).bytes));
  }

  /// Returns the current recovery-derived secret, if a recovery password has
  /// been configured. It is already encrypted at rest by secure storage.
  Future<String?> getRecoveryDerivedKey() async {
    final value = await _storage.read(key: _docKeysKey);
    if (value == null || value.isEmpty) return null;
    try {
      final keys = (jsonDecode(value) as List).whereType<String>().where((k) => k.isNotEmpty).toList();
      return keys.isEmpty ? null : keys.first;
    } catch (_) {
      return null;
    }
  }

  Future<bool> verifyRecoveryPassword(String password) async {
    final storedHash = await _storage.read(key: _recoveryPassKey);
    if (storedHash == null) return false;
    final recoverySalt = await _readSalt(AppConstants.keyRecoverySalt);
    final pinSalt = await _readSalt(AppConstants.keyPinSalt);
    return _verify(password, storedHash, [recoverySalt ?? '', pinSalt ?? '']);
  }

  Future<void> setBiometricEnabled(bool enabled) async =>
      _storage.write(key: _biometricKey, value: enabled.toString());

  Future<bool> isBiometricEnabled() async => await _storage.read(key: _biometricKey) == 'true';

  static String generateDatabaseKey({Random? rnd}) {
    final random = rnd ?? Random.secure();
    return base64UrlEncode(Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))));
  }

  static const _themeModeKey = 'pref_theme_mode';

  Future<void> setThemeMode(ThemeMode mode) async => _storage.write(key: _themeModeKey, value: mode.name);

  Future<ThemeMode> getThemeMode() async {
    final value = await _storage.read(key: _themeModeKey);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<String> getDatabaseKey() async {
    String? key = await _storage.read(key: _dbKey);
    if (key == null) {
      key = generateDatabaseKey();
      await _storage.write(key: _dbKey, value: key);
    }
    return key;
  }

  /// Replaces the local SQLCipher key only during a validated portable restore.
  Future<void> setDatabaseKey(String key) async {
    if (key.isEmpty) throw ArgumentError('Database key cannot be empty.');
    await _storage.write(key: _dbKey, value: key);
  }

  Future<String> getFileEncryptionKey() async {
    final derived = await _storage.read(key: _docKeysKey);
    if (derived != null && derived.isNotEmpty) {
      try {
        final keys = (jsonDecode(derived) as List).whereType<String>().toList();
        if (keys.isNotEmpty && keys.first.isNotEmpty) return keys.first;
      } catch (_) {}
    }
    return _getLegacyFileKey();
  }

  Future<List<String>> getDocumentDecryptionKeys() async {
    final keys = <String>[];
    final derived = await _storage.read(key: _docKeysKey);
    if (derived != null && derived.isNotEmpty) {
      try {
        keys.addAll((jsonDecode(derived) as List).whereType<String>());
      } catch (_) {}
    }
    final legacy = await _storage.read(key: _fileEncryptionKey);
    if (legacy != null && legacy.isNotEmpty && !keys.contains(legacy)) keys.add(legacy);
    return keys;
  }

  Future<String> _getLegacyFileKey() async {
    String? key = await _storage.read(key: _fileEncryptionKey);
    if (key == null) {
      key = const Uuid().v4();
      await _storage.write(key: _fileEncryptionKey, value: key);
    }
    return key;
  }
}
