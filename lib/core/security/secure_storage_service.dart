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

  // PBKDF2-HMAC-SHA256 iterations. The PIN is a 4-digit secret guarded by the
  // escalating lockout (PinLockoutService), so 120k keeps unlock instant even
  // on low-end phones. The recovery password is the high-value escape hatch
  // (verified rarely), so it uses the OWASP-recommended 600k.
  static const _pinIterations = 120000;
  static const _recoveryIterations = 600000;
  static const _pinHashLength = 32;

  /// Fixed, well-known salt for deriving the document-encryption key from the
  /// recovery password. Deliberately NOT per-device: the same recovery password
  /// entered on a second device must derive the same key so cloud-synced
  /// encrypted documents can be decrypted cross-device (API-6). The recovery
  /// password is a high-entropy secret unique to this app, so the fixed salt
  /// leaks nothing without the password.
  static const String docDerivationSalt = 'loantrack-doc-key-v1';

  /// Iterations for the document-key derivation. Runs only when the recovery
  /// password is set or changed (never on the encrypt/decrypt hot path — the
  /// derived key is cached in secure storage), so it can share the recovery
  /// password's 600k.
  static const int _docDerivedIterations = 600000;

  /// How many derived document keys are retained after a recovery-password
  /// change, so files encrypted under a previous password stay decryptable.
  static const int _maxDocKeys = 5;

  /// Returns the per-device random salt for the given purpose, creating and
  /// storing it on first use so hashes stay stable across writes.
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

  /// Runs the CPU-bound PBKDF2 derivation off the main isolate. The recovery
  /// password path hashes at 600k iterations (twice per save: the stored hash
  /// plus the derived document key), which on low-end phones can block the UI
  /// for multiple seconds if computed inline. Isolating keeps the PIN/recovery
  /// screens responsive and the navigation to the next screen (e.g. the cloud
  /// gate right after PIN setup) snappy.
  static Future<String> _pbkdf2HexAsync(
      String data, String salt, int iterations) {
    return Isolate.run(() => _pbkdf2Hex(data, salt, iterations));
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
  Future<String> _hash(String data, String saltKey, int iterations) async {
    final salt = await _getSalt(saltKey);
    final digest = await _pbkdf2HexAsync(data, salt, iterations);
    return 'pbkdf2-sha256:$iterations:$digest';
  }

  /// Verifies [data] against [stored]. [saltCandidates] are tried in order so
  /// hashes created before a salt split (recovery vs PIN) still verify.
  Future<bool> _verify(
      String data, String stored, List<String> saltCandidates) async {
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

  /// Enforces a strong recovery password: at least 16 characters (OWASP,
  /// raised from 12 on 2026-08-04) containing both letters and digits. Returns
  /// null when [password] is acceptable.
  static String? recoveryPasswordError(String password) {
    if (password.length < 16) {
      return 'Recovery password must be at least 16 characters';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Recovery password must contain both letters and numbers';
    }
    return null;
  }

  Future<void> savePin(String pin) async {
    await _storage.write(
        key: _pinKey,
        value: await _hash(pin, AppConstants.keyPinSalt, _pinIterations));
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
    final pinSalt = await _readSalt(AppConstants.keyPinSalt);
    return _verify(pin, storedHash, [pinSalt ?? '']);
  }

  Future<bool> hasPin() async {
    final storedHash = await _storage.read(key: _pinKey);
    return storedHash != null;
  }

  Future<void> saveRecoveryPassword(String password) async {
    await _storage.write(
        key: _recoveryPassKey,
        value:
            await _hash(password, AppConstants.keyRecoverySalt, _recoveryIterations));
    await _storeDerivedDocKey(password);
  }

  /// Derives the document-encryption key from the recovery password and caches
  /// it (newest first, capped at [_maxDocKeys]) so files encrypted under an
  /// older recovery password remain decryptable after a change. Any device that
  /// knows the same recovery password derives the same key, which is what lets
  /// cloud-synced encrypted documents open on a second device.
  Future<void> _storeDerivedDocKey(String password) async {
    final derived =
        await _pbkdf2HexAsync(password, docDerivationSalt, _docDerivedIterations);
    final existing = await _storage.read(key: _docKeysKey);
    final List<String> keys;
    if (existing == null || existing.isEmpty) {
      keys = [derived];
    } else {
      List<String> parsed;
      try {
        parsed = [
          derived,
          ...(jsonDecode(existing) as List)
              .whereType<String>()
              .where((k) => k != derived),
        ];
      } catch (_) {
        parsed = [derived];
      }
      keys = parsed;
    }
    await _storage.write(
        key: _docKeysKey,
        value: jsonEncode(keys.take(_maxDocKeys).toList()));
  }

  /// The deterministic document-encryption key derived from [password]. Exposed
  /// as a pure function (with an overridable iteration count) so the derivation
  /// contract — same password, same key, cross-device — is unit-testable.
  static String deriveDocumentKey(String password, {int iterations = 600000}) {
    return _pbkdf2Hex(password, docDerivationSalt, iterations);
  }

  Future<bool> verifyRecoveryPassword(String password) async {
    final storedHash = await _storage.read(key: _recoveryPassKey);
    if (storedHash == null) return false;
    // Try the dedicated recovery salt first, then fall back to the PIN salt
    // so hashes created before the salt split still verify.
    final recoverySalt = await _readSalt(AppConstants.keyRecoverySalt);
    final pinSalt = await _readSalt(AppConstants.keyPinSalt);
    return _verify(
        password, storedHash, [recoverySalt ?? '', pinSalt ?? '']);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled.toString());
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _biometricKey);
    return value == 'true';
  }

  /// Generates a base64url-encoded 32-byte key using [rnd] or a secure RNG.
  /// Exposed as a static helper for unit testing.
  static String generateDatabaseKey({Random? rnd}) {
    final random = rnd ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(Uint8List.fromList(bytes));
  }

  static const _themeModeKey = 'pref_theme_mode';

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.write(key: _themeModeKey, value: mode.name);
  }

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
      // Generate and persist the key.
      key = generateDatabaseKey();
      await _storage.write(key: _dbKey, value: key);
    }
    return key;
  }

  /// Returns the primary document-encryption key used for NEW encryption: the
  /// key derived from the recovery password when one has been set (so a second
  /// device with the same recovery password decrypts the same files), otherwise
  /// the legacy per-device random key.
  Future<String> getFileEncryptionKey() async {
    final derived = await _storage.read(key: _docKeysKey);
    if (derived != null && derived.isNotEmpty) {
      try {
        final keys =
            (jsonDecode(derived) as List).whereType<String>().toList();
        if (keys.isNotEmpty && keys.first.isNotEmpty) return keys.first;
      } catch (_) {
        // Fall through to the legacy key on corrupt state.
      }
    }
    return _getLegacyFileKey();
  }

  /// Every key that may open an existing encrypted document, newest derived key
  /// first, the legacy per-device random key last. Files encrypted before a
  /// recovery password existed (or before a password change) stay readable.
  Future<List<String>> getDocumentDecryptionKeys() async {
    final keys = <String>[];
    final derived = await _storage.read(key: _docKeysKey);
    if (derived != null && derived.isNotEmpty) {
      try {
        keys.addAll((jsonDecode(derived) as List).whereType<String>());
      } catch (_) {
        // Ignore corrupt derived-key state; the legacy key may still work.
      }
    }
    final legacy = await _storage.read(key: _fileEncryptionKey);
    if (legacy != null && legacy.isNotEmpty && !keys.contains(legacy)) {
      keys.add(legacy);
    }
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
