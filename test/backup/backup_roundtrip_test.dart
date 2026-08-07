import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/backup/data/backup_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points [getApplicationDocumentsDirectory] at a temp folder so the backup
/// service's on-disk artifacts (backup dir + secure_documents/) are test-local.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// A [DatabaseService] whose live DB is a real SQLite file under the test temp
/// folder, so the backup/restore file mechanics (encrypt, ZIP, safe swap) run
/// against actual bytes instead of a mocked file system.
class _FakeBackupDatabaseService extends DatabaseService {
  _FakeBackupDatabaseService(this._db, this.path, SecureStorageService storage)
      : super(storage);

  Database _db;
  final String path;

  @override
  Future<Database> get database async => _db;

  @override
  Future<String> get databasePath async => path;

  /// Mirrors the real close -> action -> reopen cycle, reopening the FFI
  /// connection on the same temp file so a test can keep querying afterwards.
  @override
  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    await _db.close();
    try {
      return await action();
    } finally {
      _db = await databaseFactoryFfi.openDatabase(path);
    }
  }

  /// The SQLCipher verify step is out of scope for these tests — the encrypted
  /// container/ZIP/swap mechanics are the unit under test.
  @override
  Future<bool> verifyDatabaseFile(String path) async => true;

  Future<void> closeDb() async {
    try {
      await _db.close();
    } catch (_) {
      // Best-effort close; tearDown must not fail on an already-closed DB.
    }
  }
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    originalPathProvider = PathProviderPlatform.instance;
    tempDir = Directory.systemTemp.createTempSync('backup_roundtrip_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
  });

  Future<Database> openLiveDb(String path) async {
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        date_registered TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        amount REAL NOT NULL,
        receipt_no TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
    await db.insert('customers', {
      'id': 'c1',
      'full_name': 'Ada Obi',
      'phone': '08012345678',
      'date_registered': '2026-01-05',
      'status': 'active',
    });
    await db.insert('loans', {
      'id': 'L1',
      'customer_id': 'c1',
      'amount': 3000.0,
      'total_repayment': 3300.0,
      'outstanding_balance': 2500.0,
      'status': 'active',
    });
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'amount': 800.0,
      'receipt_no': 'RCV-001',
      'status': 'completed',
    });
    return db;
  }

  Future<(BackupService, _FakeBackupDatabaseService)> buildHarness(
      String dbKey) async {
    final dbPath = p.join(tempDir.path, AppConstants.databaseName);
    final db = await openLiveDb(dbPath);
    final storage = _MockFlutterSecureStorage();
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => dbKey);
    final secureStorage = SecureStorageService(storage: storage);
    final service = _FakeBackupDatabaseService(db, dbPath, secureStorage);
    return (BackupService(service, secureStorage), service);
  }

  test('encrypted backup/restore round-trip preserves DB and documents',
      () async {
    final (backup, service) = await buildHarness('test-db-key');
    // Delete AFTER the DB is closed (LIFO: closeDb is registered last).
    addTearDown(service.closeDb);
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // A lingering handle must not fail the test.
      }
    });

    // A customer document to prove secure_documents/ is included in the backup.
    final docsDir = Directory(p.join(tempDir.path, 'secure_documents'));
    await docsDir.create(recursive: true);
    final docBytes = List<int>.generate(64, (i) => i % 251);
    await File(p.join(docsDir.path, 'c1-passport.enc'))
        .writeAsBytes(docBytes, flush: true);

    final file = await backup.createBackup();
    expect(file.path, endsWith(AppConstants.backupFileExtension));
    final bytes = await file.readAsBytes();
    expect(BackupService.isEncryptedContainer(bytes), isTrue);
    expect(BackupService.isSqliteFile(bytes), isFalse);

    // Mutate the live DB so a successful restore must overwrite this state.
    final db = await service.database;
    await db.delete('payments', where: 'id = ?', whereArgs: ['P1']);
    await db.insert('customers', {
      'id': 'c2',
      'full_name': 'Bola Yusuf',
      'phone': '08098765432',
      'date_registered': '2026-07-01',
      'status': 'active',
    });
    await db.update('loans', {'status': 'completed', 'outstanding_balance': 0.0},
        where: 'id = ?', whereArgs: ['L1']);
    await File(p.join(docsDir.path, 'c1-passport.enc')).delete();

    await backup.restoreBackup(file);

    final restored = await service.database;
    final customers = await restored.query('customers', orderBy: 'id');
    expect(customers.map((c) => c['id']), ['c1']); // c2 gone after restore.
    final payments = await restored.query('payments');
    expect(payments.single['id'], 'P1'); // deleted payment restored.
    final loans = await restored.query('loans');
    expect(loans.single['status'], 'active');
    expect(loans.single['outstanding_balance'], 2500.0);
    expect(
      await File(p.join(docsDir.path, 'c1-passport.enc')).readAsBytes(),
      docBytes,
    );
  });

  test('a backup from a different app key is rejected and the live DB is '
      'untouched', () async {
    final (backupA, service) = await buildHarness('key-a');
    addTearDown(service.closeDb);
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // A lingering handle must not fail the test.
      }
    });

    final file = await backupA.createBackup();

    // Tamper the live data; a failed restore must not roll this back.
    final db = await service.database;
    await db.insert('customers', {
      'id': 'c2',
      'full_name': 'Bola Yusuf',
      'phone': '08098765432',
      'date_registered': '2026-07-01',
      'status': 'active',
    });

    // A second install with a different app key cannot decrypt the container.
    final storage = _MockFlutterSecureStorage();
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'key-b');
    final backupB = BackupService(service, SecureStorageService(storage: storage));

    await expectLater(
      backupB.restoreBackup(file),
      throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('different app key'))),
    );

    final unchanged = await service.database;
    final customers = await unchanged.query('customers', orderBy: 'id');
    expect(customers.map((c) => c['id']), ['c1', 'c2']);
  });
}
