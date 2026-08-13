import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/security/file_encryption_service.dart';
import 'models/document_entity.dart';

class DocumentRepository {
  DocumentRepository(this._ref);
  final Ref _ref;

  Future<Database> get _database async {
    final service = await _ref.read(databaseServiceProvider.future);
    return service.database;
  }

  FileEncryptionService get _encryption => _ref.read(fileEncryptionProvider);

  Future<List<CustomerDocument>> forCustomer(String customerId) async {
    final db = await _database;
    final records = await db.query(
      'documents',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'uploaded_at DESC',
    );
    return records.map(CustomerDocument.fromMap).toList(growable: false);
  }

  Future<CustomerDocument> add({
    required String customerId,
    required CustomerDocumentType type,
    required File source,
    String? loanId,
  }) async {
    final mimeType = await _validateSource(source);
    final encryptedPath = await _encryption.encryptFile(source);
    final document = CustomerDocument(
      id: const Uuid().v4(),
      customerId: customerId,
      loanId: loanId,
      type: type,
      encryptedPath: encryptedPath,
      originalName: path.basename(source.path),
      mimeType: mimeType,
      uploadedAt: DateTime.now(),
    );
    try {
      final db = await _database;
      await db.insert('documents', document.toMap());
      return document;
    } catch (_) {
      await _encryption.delete(encryptedPath);
      rethrow;
    }
  }

  Future<CustomerDocument> replace(
      CustomerDocument current, File source) async {
    final mimeType = await _validateSource(source);
    final replacement = await _encryption.encryptFile(source);
    final updated = CustomerDocument(
      id: current.id,
      customerId: current.customerId,
      loanId: current.loanId,
      type: current.type,
      encryptedPath: replacement,
      originalName: path.basename(source.path),
      mimeType: mimeType,
      uploadedAt: DateTime.now(),
    );
    try {
      final db = await _database;
      await db.update('documents', updated.toMap(),
          where: 'id = ?', whereArgs: [current.id]);
      // The row now references [replacement]; a failure to remove the old file
      // must not fall into the catch below, which would delete the new file the
      // row already points at and orphan an undecryptable document. The old
      // file is disposable — ignore any delete error.
      try {
        await _encryption.delete(current.encryptedPath);
      } catch (_) {
        // Old file already gone or unreadable; the DB is the source of truth.
      }
      return updated;
    } catch (_) {
      await _encryption.delete(replacement);
      rethrow;
    }
  }

  Future<void> delete(CustomerDocument document) async {
    final db = await _database;
    await db.delete('documents', where: 'id = ?', whereArgs: [document.id]);
    await _encryption.delete(document.encryptedPath);
  }

  /// Decrypts [document] and verifies the recovered bytes are actually one of
  /// the supported formats (PDF/PNG/JPEG) before they reach any parser.
  /// Returns the plaintext together with the MIME type detected from the file
  /// *content* (never the stored metadata), so callers render with the real
  /// format. Throws [FileEncryptionException] for a format mismatch.
  Future<({Uint8List bytes, String mimeType})> decrypt(
      CustomerDocument document) async {
    final bytes = await _encryption.decryptFile(document.encryptedPath);
    final mimeType = detectDocumentMimeType(bytes);
    if (mimeType == null) {
      throw const FileEncryptionException(
        'This document could not be verified as a valid PDF, PNG, JPG, or JPEG file.',
      );
    }
    return (bytes: bytes, mimeType: mimeType);
  }

  /// Validates [source] and returns the MIME type detected from its content.
  Future<String> _validateSource(File source) async {
    final length = await source.length();
    if (length == 0) {
      throw const DocumentFileException('The selected file is empty.');
    }
    if (length > AppConstants.maxDocumentSizeBytes) {
      throw const DocumentFileException('Documents must be 20 MB or smaller.');
    }
    // Read only the header bytes needed for signature detection.
    final buffer = <int>[];
    await for (final chunk in source.openRead(0, 32)) {
      buffer.addAll(chunk);
      if (buffer.length >= 32) break;
    }
    final mimeType = detectDocumentMimeType(Uint8List.fromList(buffer));
    if (mimeType == null) {
      throw const DocumentFileException(
          'Only valid PDF, PNG, JPG, and JPEG documents are supported.');
    }
    return mimeType;
  }
}

/// Detects the MIME type of a document from its magic bytes.
///
/// The cloud cannot scan content (documents are end-to-end encrypted before
/// upload), so this client-side content gate is the security boundary: a file
/// that merely has an approved extension but renamed content (e.g. `malware.exe`
/// renamed to `loan.pdf`) is rejected. Returns the content-derived MIME type or
/// `null` for an unrecognized/unsupported signature.
String? detectDocumentMimeType(Uint8List bytes) {
  if (bytes.length >= 5 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46 && // F
      bytes[4] == 0x2D) {
    return 'application/pdf';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 && // P
      bytes[2] == 0x4E && // N
      bytes[3] == 0x47 && // G
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  return null;
}

class DocumentFileException implements Exception {
  const DocumentFileException(this.message);
  final String message;

  @override
  String toString() => message;
}
