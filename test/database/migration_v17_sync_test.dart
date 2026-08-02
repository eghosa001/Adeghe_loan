import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Validates the v17 cloud-sync migration with a real SQLite engine:
///  * `updated_at` columns are added to every replicated table and back-filled
///  * the sync bookkeeping tables and stamp/tombstone triggers are created
///  * a normal write stamps `updated_at` and records a tombstone on delete
///  * `sync_flags.pull_in_progress = '1'` suppresses both (pull writes keep
///    the remote timestamp and are not re-pushed / re-tombstoned)
void main() {
  sqfliteFfiInit();

  Future<Database> openV16Database() async {
    final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath, options: OpenDatabaseOptions(version: 16));
    await db.execute('CREATE TABLE business_profile (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('CREATE TABLE customer_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE customers (id TEXT PRIMARY KEY, full_name TEXT NOT NULL, phone TEXT UNIQUE NOT NULL, date_registered TEXT NOT NULL, status TEXT NOT NULL)');
    await db.execute('CREATE TABLE loans (id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, amount REAL NOT NULL, status TEXT NOT NULL)');
    await db.execute('CREATE TABLE repayment_schedule (id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, installment_number INTEGER NOT NULL, amount REAL NOT NULL)');
    await db.execute('CREATE TABLE payments (id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, amount REAL NOT NULL, receipt_no TEXT UNIQUE NOT NULL, status TEXT NOT NULL)');
    await db.execute('CREATE TABLE savings_accounts (id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, balance REAL NOT NULL)');
    await db.execute('CREATE TABLE savings_transactions (id TEXT PRIMARY KEY, savings_account_id TEXT NOT NULL, amount REAL NOT NULL)');
    await db.execute('CREATE TABLE documents (id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, file_path TEXT NOT NULL)');
    await db.execute('CREATE TABLE holidays (id TEXT PRIMARY KEY, name TEXT NOT NULL, date TEXT NOT NULL, is_recurring INTEGER NOT NULL, is_enabled INTEGER NOT NULL)');
    await db.execute('CREATE TABLE audit_logs (id TEXT PRIMARY KEY, user TEXT NOT NULL, action TEXT NOT NULL, timestamp TEXT NOT NULL, details TEXT NOT NULL)');
    await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    return db;
  }

  Future<Set<String>> tableNames(Database db) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'");
    return rows.map((row) => row['name'] as String).toSet();
  }

  Future<Set<String>> triggerNames(Database db) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger'");
    return rows.map((row) => row['name'] as String).toSet();
  }

  test('v17 adds updated_at columns and creates the sync schema', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 16, 17);

    final tables = await tableNames(db);
    expect(tables, containsAll(['sync_flags', 'sync_meta', 'sync_tombstones']));

    for (final table in const [
      'business_profile',
      'customer_groups',
      'customers',
      'loans',
      'repayment_schedule',
      'payments',
      'savings_accounts',
      'savings_transactions',
      'documents',
      'holidays',
      'audit_logs',
      'settings',
    ]) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final names = columns.map((c) => c['name']).toSet();
      expect(names, contains('updated_at'),
          reason: '$table should have updated_at after v17');
    }

    final triggers = await triggerNames(db);
    for (final table in const ['customers', 'settings']) {
      expect(triggers, contains('trg_${table}_ins'));
      expect(triggers, contains('trg_${table}_upd'));
      expect(triggers, contains('trg_${table}_del'));
    }
  });

  test('v17 back-fills updated_at for pre-existing rows', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await db.insert('customers', {
      'id': 'c1',
      'full_name': 'Old Customer',
      'phone': '08000000001',
      'date_registered': '2026-01-01',
      'status': 'active',
    });

    await DatabaseMigrations.run(db, 16, 17);

    final rows = await db.query('customers');
    expect(rows.single['updated_at'], isNotNull);
    expect(rows.single['updated_at'] as String,
        matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'));
  });

  test('normal writes stamp updated_at and deletes create tombstones', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 16, 17);

    await db.insert('customers', {
      'id': 'c1',
      'full_name': 'Ada',
      'phone': '08000000002',
      'date_registered': '2026-01-01',
      'status': 'active',
    });
    var customer =
        (await db.query('customers', where: 'id = ?', whereArgs: ['c1'])).single;
    final stampedAt = customer['updated_at'] as String;
    expect(stampedAt, isNotNull);

    // An update refreshes the timestamp.
    await db.update('customers', {'status': 'archived'},
        where: 'id = ?', whereArgs: ['c1']);
    customer =
        (await db.query('customers', where: 'id = ?', whereArgs: ['c1'])).single;
    expect((customer['updated_at'] as String).compareTo(stampedAt) > 0, isTrue);

    // A delete records a tombstone (cascaded deletes would too).
    await db.delete('customers', where: 'id = ?', whereArgs: ['c1']);
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, hasLength(1));
    expect(tombstones.single['deleted_table'], 'customers');
    expect(tombstones.single['deleted_row_id'], 'c1');
  });

  test('settings table stamps via its key primary key', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 16, 17);

    await db.insert('settings', {'key': 'currency', 'value': 'NGN'});
    final row = (await db.query('settings', where: 'key = ?', whereArgs: ['currency'])).single;
    expect(row['updated_at'], isNotNull);

    await db.delete('settings', where: 'key = ?', whereArgs: ['currency']);
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones.single['deleted_row_id'], 'currency');
  });

  test('pull-in-progress flag suppresses stamping and tombstones', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 16, 17);

    await db.insert('sync_flags', {'key': 'pull_in_progress', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('customers', {
      'id': 'c1',
      'full_name': 'Ada',
      'phone': '08000000003',
      'date_registered': '2026-01-01',
      'status': 'active',
      'updated_at': '2026-08-01T10:00:00.000Z',
    });
    final row = (await db.query('customers', where: 'id = ?', whereArgs: ['c1'])).single;
    // The remote timestamp is preserved — the trigger did not run.
    expect(row['updated_at'], '2026-08-01T10:00:00.000Z');

    await db.delete('customers', where: 'id = ?', whereArgs: ['c1']);
    expect(await db.query('sync_tombstones'), isEmpty);

    // Turning the flag back off restores normal tracking.
    await db.insert('sync_flags', {'key': 'pull_in_progress', 'value': '0'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('customers', {
      'id': 'c2',
      'full_name': 'Bola',
      'phone': '08000000004',
      'date_registered': '2026-01-01',
      'status': 'active',
    });
    final row2 = (await db.query('customers', where: 'id = ?', whereArgs: ['c2'])).single;
    expect(row2['updated_at'], isNotNull);
  });
}
