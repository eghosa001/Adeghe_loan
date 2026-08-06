import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import 'secure_storage_service.dart';

/// Encrypts customer documents before they are persisted on disk.
///
/// Encrypted files contain a small format marker, a random IV, and the AES-GCM
/// ciphertext. They can only be opened on a device that has the matching secret.
/// The secret is derived from the recovery password (deterministic — the same
/// password on a second device yields the same key), with a legacy per-device
/// random key kept as a decryption fallback for files created before a recovery
/// password existed.
class FileEncryptionService {
  FileEncryptionService(this._secureStorage);

  static const _header = [0x4c, 0x54, 0x44, 0x31]; // LTD1
  static const _ivLength = 12; // Standard for GCM
  final SecureStorageService _secureStorage;

  Future<String> encryptFile(File source) async {
    final bytes = await source.readAsBytes();
    final key = await _secureStorage.getFileEncryptionKey();
    // GCM is CPU-bound pure Dart; run it off the UI isolate so a multi-MB
    // document cannot jank the screen during upload.
    final encrypted =
        await Isolate.run(() => _encryptInIsolate(bytes, key));
    final root = await getApplicationDocumentsDirectory();
    final directory =
        Directory('${root.path}${Platform.pathSeparator}secure_documents');
    if (!await directory.exists()) await directory.create(recursive: true);
    final path =
        '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.enc';
    await File(path).writeAsBytes(encrypted, flush: true);
    return path;
  }

  Future<Uint8List> decryptFile(String encryptedPath) async {
    Uint8List payload;
    try {
      payload = await File(encryptedPath).readAsBytes();
    } catch (_) {
      throw FileEncryptionException(
          'Unable to read the document file. It may have been moved or deleted.');
    }
    if (payload.length <= _header.length + _ivLength ||
        !_matchesHeader(payload)) {
      throw FileEncryptionException(
          'This document is not a valid encrypted ${AppConstants.appName} file.');
    }
    // Try every key that may open this file: the current recovery-password-
    // derived key first, older derived keys (previous recovery passwords), then
    // the legacy per-device random key. A second device that knows the recovery
    // password decrypts the same files (API-6). Run off the UI isolate.
    final keySecrets = await _secureStorage.getDocumentDecryptionKeys();
    final decrypted =
        await Isolate.run(() => _decryptInIsolate(payload, keySecrets));
    if (decrypted == null) {
      throw const FileEncryptionException('Unable to decrypt this document. The file may be corrupt or the key may have changed.');
    }
    return decrypted;
  }

  static Uint8List _encryptInIsolate(Uint8List source, String keySecret) {
    final iv = encrypt.IV.fromSecureRandom(_ivLength);
    final encrypter = encrypt.Encrypter(
        encrypt.AES(_toKey(keySecret), mode: encrypt.AESMode.gcm));
    final cipher = encrypter.encryptBytes(source, iv: iv);
    return Uint8List.fromList([..._header, ...iv.bytes, ...cipher.bytes]);
  }

  /// Returns null when the payload is malformed or none of the candidate keys
  /// decrypts it (GCM authentication fails), so the caller can throw a typed
  /// [FileEncryptionException] with the right message.
  static Uint8List? _decryptInIsolate(
      Uint8List payload, List<String> keySecrets) {
    if (payload.length <= _header.length + _ivLength) return null;
    for (var index = 0; index < _header.length; index++) {
      if (payload[index] != _header[index]) return null;
    }
    final ivStart = _header.length;
    final iv = encrypt.IV(payload.sublist(ivStart, ivStart + _ivLength));
    final ciphertext = payload.sublist(ivStart + _ivLength);
    for (final keySecret in keySecrets) {
      try {
        final encrypter = encrypt.Encrypter(
            encrypt.AES(_toKey(keySecret), mode: encrypt.AESMode.gcm));
        return Uint8List.fromList(
            encrypter.decryptBytes(encrypt.Encrypted(ciphertext), iv: iv));
      } catch (_) {
        // Try the next candidate key.
      }
    }
    return null;
  }

  static encrypt.Key _toKey(String secret) => encrypt.Key(
      Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes));

  bool _matchesHeader(Uint8List payload) {
    for (var index = 0; index < _header.length; index++) {
      if (payload[index] != _header[index]) return false;
    }
    return true;
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class FileEncryptionException implements Exception {
  const FileEncryptionException(this.message);
  final String message;

  @override
  String toString() => message;
}
