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

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _FakeBackupDatabaseService extends DatabaseService {
  _FakeBackupDatabaseService(this._db, this.path, SecureStorageService storage) : super(storage);
  Database _db;
  final String path;

  @override
  Future<Database> get database async => _db;
  @override
  Future<String> get databasePath async => path;
  @override
  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    await _db.close();
    try {
      return await action();
    } finally {
      _db = await databaseFactoryFfi.openDatabase(path);
    }
  }
  @override
  Future<bool> verifyDatabaseFile(String path, {String? encryptionKey}) async => true;

  Future<void> closeDb() async {
    try { await _db.close(); } catch (_) {}
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

  tearDown(() => PathProviderPlatform.instance = originalPathProvider);

  Future<Database> openLiveDb(String dbPath) async {
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, full_name TEXT NOT NULL, phone TEXT NOT NULL, date_registered TEXT NOT NULL, status TEXT NOT NULL)');
    await db.execute('CREATE TABLE loans (id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, amount REAL NOT NULL, total_repayment REAL NOT NULL, outstanding_balance REAL NOT NULL, status TEXT NOT NULL)');
    await db.execute('CREATE TABLE payments (id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, receipt_no TEXT NOT NULL, status TEXT NOT NULL)');
    await db.insert('customers', {'id': 'c1', 'full_name': 'Ada Obi', 'phone': '08012345678', 'date_registered': '2026-01-05', 'status': 'active'});
    await db.insert('loans', {'id': 'L1', 'customer_id': 'c1', 'amount': 3000.0, 'total_repayment': 3300.0, 'outstanding_balance': 2500.0, 'status': 'active'});
    await db.insert('payments', {'id': 'P1', 'loan_id': 'L1', 'amount': 800.0, 'receipt_no': 'RCV-001', 'status': 'completed'});
    return db;
  }

  Future<(BackupService, _FakeBackupDatabaseService)> buildHarness(String dbKey) async {
    final dbPath = p.join(tempDir.path, AppConstants.databaseName);
    final db = await openLiveDb(dbPath);
    final storage = _MockFlutterSecureStorage();
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => dbKey);
    when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
    final secureStorage = SecureStorageService(storage: storage);
    final service = _FakeBackupDatabaseService(db, dbPath, secureStorage);
    return (BackupService(service, secureStorage), service);
  }

  Future<void> cleanup(_FakeBackupDatabaseService service) async {
    await service.closeDb();
    try { tempDir.deleteSync(recursive: true); } catch (_) {}
  }

  test('portable encrypted backup restores database and documents', () async {
    final (backup, service) = await buildHarness('test-db-key');
    addTearDown(() => cleanup(service));
    final docsDir = Directory(p.join(tempDir.path, 'secure_documents'))..createSync(recursive: true);
    final docBytes = List<int>.generate(64, (i) => i % 251);
    await File(p.join(docsDir.path, 'c1-passport.enc')).writeAsBytes(docBytes, flush: true);

    final file = await backup.createBackup(recoveryPassword: 'CorrectHorseBattery123');
    final bytes = await file.readAsBytes();
    expect(BackupService.isPortableContainer(bytes), isTrue);
    expect(BackupService.isEncryptedContainer(bytes), isTrue);

    final db = await service.database;
    await db.delete('payments', where: 'id = ?', whereArgs: ['P1']);
    await db.insert('customers', {'id': 'c2', 'full_name': 'Bola Yusuf', 'phone': '08098765432', 'date_registered': '2026-07-01', 'status': 'active'});
    await db.update('loans', {'status': 'completed', 'outstanding_balance': 0.0}, where: 'id = ?', whereArgs: ['L1']);
    await File(p.join(docsDir.path, 'c1-passport.enc')).delete();

    await backup.restoreBackup(file, recoveryPassword: 'CorrectHorseBattery123');
    final restored = await service.database;
    expect((await restored.query('customers', orderBy: 'id')).map((c) => c['id']), ['c1']);
    expect((await restored.query('payments')).single['id'], 'P1');
    expect((await restored.query('loans')).single['status'], 'active');
    expect((await restored.query('loans')).single['outstanding_balance'], 2500.0);
    expect(await File(p.join(docsDir.path, 'c1-passport.enc')).readAsBytes(), docBytes);
  });

  test('wrong recovery password cannot alter the live database', () async {
    final (backup, service) = await buildHarness('key-a');
    addTearDown(() => cleanup(service));
    final file = await backup.createBackup(recoveryPassword: 'CorrectHorseBattery123');
    final db = await service.database;
    await db.update('loans', {'status': 'completed'}, where: 'id = ?', whereArgs: ['L1']);

    await expectLater(
      backup.restoreBackup(file, recoveryPassword: 'WrongHorseBattery123'),
      throwsA(isA<Exception>()),
    );
    expect((await service.database.query('loans')).single['status'], 'completed');
  });
}
