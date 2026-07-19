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
    await _validateSource(source);
    final encryptedPath = await _encryption.encryptFile(source);
    final document = CustomerDocument(
      id: const Uuid().v4(),
      customerId: customerId,
      loanId: loanId,
      type: type,
      encryptedPath: encryptedPath,
      originalName: path.basename(source.path),
      mimeType: _mimeTypeFor(source.path),
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
    await _validateSource(source);
    final replacement = await _encryption.encryptFile(source);
    final updated = CustomerDocument(
      id: current.id,
      customerId: current.customerId,
      loanId: current.loanId,
      type: current.type,
      encryptedPath: replacement,
      originalName: path.basename(source.path),
      mimeType: _mimeTypeFor(source.path),
      uploadedAt: DateTime.now(),
    );
    try {
      final db = await _database;
      await db.update('documents', updated.toMap(),
          where: 'id = ?', whereArgs: [current.id]);
      await _encryption.delete(current.encryptedPath);
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

  Future<Uint8List> decrypt(CustomerDocument document) =>
      _encryption.decryptFile(document.encryptedPath);

  String _mimeTypeFor(String filePath) {
    return switch (path.extension(filePath).toLowerCase()) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _validateSource(File source) async {
    if (_mimeTypeFor(source.path) == 'application/octet-stream') {
      throw const DocumentFileException(
          'Only PDF, PNG, JPG, and JPEG documents are supported.');
    }
    if (await source.length() > AppConstants.maxDocumentSizeBytes) {
      throw const DocumentFileException('Documents must be 20 MB or smaller.');
    }
  }
}

class DocumentFileException implements Exception {
  const DocumentFileException(this.message);
  final String message;

  @override
  String toString() => message;
}
