import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/security/file_encryption_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/documents/data/models/document_entity.dart';
import 'package:loantrack/features/documents/presentation/providers/document_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show
        OpenDatabaseOptions,
        databaseFactoryFfi,
        inMemoryDatabasePath,
        sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());

  final Database _db;

  @override
  Future<Database> get database async => _db;
}

/// Fake encryption whose `delete` can be made to throw for chosen paths (a
/// real FileSystemException when the file is unreadable / permission denied).
class _FakeEncryption extends FileEncryptionService {
  _FakeEncryption() : super(SecureStorageService());

  final Set<String> _failOnDelete = {};
  final List<String> deleteCalls = [];
  final List<String> createdPaths = [];

  void failOn(String path) => _failOnDelete.add(path);

  @override
  Future<String> encryptFile(File source) async {
    final dir = await Directory.systemTemp.createTemp('doc_replace_enc');
    final file = File(
        '${dir.path}${Platform.pathSeparator}enc_${DateTime.now().microsecondsSinceEpoch}.enc');
    await file.writeAsBytes([1, 2, 3]);
    createdPaths.add(file.path);
    return file.path;
  }

  @override
  Future<void> delete(String path) async {
    deleteCalls.add(path);
    if (_failOnDelete.contains(path)) {
      throw FileSystemException('Simulated delete failure', path);
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

Future<File> _pdfSource() async {
  final dir = await Directory.systemTemp.createTemp('doc_replace_src');
  final file = File('${dir.path}${Platform.pathSeparator}passport.pdf');
  await file.writeAsBytes(utf8.encode('%PDF-1.4\n% fake pdf payload'));
  return file;
}

void main() {
  sqfliteFfiInit();

  test('replace() keeps the new file when deleting the old one fails', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_id TEXT,
        doc_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        uploaded_at TEXT NOT NULL
      )
    ''');

    final fakeEncryption = _FakeEncryption();
    final container = ProviderContainer(overrides: [
      databaseServiceProvider.overrideWith((ref) async => _FakeDatabaseService(db)),
      fileEncryptionProvider.overrideWith((ref) => fakeEncryption),
    ]);
    addTearDown(container.dispose);

    final repo = container.read(documentRepositoryProvider);
    final doc = await repo.add(
      customerId: 'C1',
      type: CustomerDocumentType.passport,
      source: await _pdfSource(),
    );
    final oldPath = doc.encryptedPath;

    // Simulate an I/O failure while removing the old encrypted file.
    fakeEncryption.failOn(oldPath);

    final updated = await repo.replace(doc, await _pdfSource());

    // The DB row now references the replacement, so the replacement file must
    // survive even though removing the old file failed.
    expect(updated.encryptedPath, isNot(oldPath));
    expect(await File(updated.encryptedPath).exists(), isTrue);
    expect(fakeEncryption.deleteCalls, contains(oldPath));

    final rows = await db.query('documents',
        where: 'id = ?', whereArgs: [doc.id]);
    expect(rows.single['file_path'], updated.encryptedPath);
  });

  test('replace() still cleans up the new file when the DB update fails',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        doc_type TEXT NOT NULL,
        file_path TEXT NOT NULL
      )
    ''');

    final fakeEncryption = _FakeEncryption();
    final container = ProviderContainer(overrides: [
      databaseServiceProvider.overrideWith((ref) async => _FakeDatabaseService(db)),
      fileEncryptionProvider.overrideWith((ref) => fakeEncryption),
    ]);
    addTearDown(container.dispose);

    final repo = container.read(documentRepositoryProvider);
    // The row's columns do not match CustomerDocument.toMap, so db.update
    // throws (no such column) and replace() must delete the orphaned new file.
    final replacement = await _pdfSource();
    await expectLater(
      repo.replace(
        CustomerDocument(
          id: 'D1',
          customerId: 'C1',
          type: CustomerDocumentType.passport,
          encryptedPath: 'missing_old.enc',
          originalName: 'old.pdf',
          mimeType: 'application/pdf',
          uploadedAt: DateTime(2026, 1, 1),
        ),
        replacement,
      ),
      throwsA(anything),
    );
    // The new encrypted file created for the failed update must not be left
    // behind as an orphan.
    expect(fakeEncryption.createdPaths, isNotEmpty);
    expect(await File(fakeEncryption.createdPaths.last).exists(), isFalse);
  });
}
