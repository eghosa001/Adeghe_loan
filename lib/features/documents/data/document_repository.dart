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
      final changed = await db.update('documents', updated.toMap(),
          where: 'id = ?', whereArgs: [current.id]);
      if (changed != 1) {
        throw StateError('The document no longer exists and cannot be replaced.');
      }
      // The row now references [replacement]; a failure to remove the old file
      // must not delete the new file the row already points at.
      try {
        await _encryption.delete(current.encryptedPath);
      } catch (_) {
        // The old file is disposable; the DB remains the source of truth.
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

  Future<String> _validateSource(File source) async {
    final length = await source.length();
    if (length == 0) {
      throw const DocumentFileException('The selected file is empty.');
    }
    if (length > AppConstants.maxDocumentSizeBytes) {
      throw const DocumentFileException('Documents must be 20 MB or smaller.');
    }
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

String? detectDocumentMimeType(Uint8List bytes) {
  if (bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D) {
    return 'application/pdf';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
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
