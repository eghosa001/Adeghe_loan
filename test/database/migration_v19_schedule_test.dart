import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Validates the v19 migration that stops change-tracking `repayment_schedule`:
///  * the stamp/tombstone triggers created in v17 for the derived table are
///    dropped (the table is a cache recomputed from synced source data, so it
///    must not be replicated)
///  * stale repayment_schedule tombstones are purged
///  * every OTHER table's change tracking is untouched
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

  Future<Set<String>> triggerNames(Database db) async {
    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger'");
    return rows.map((row) => row['name'] as String).toSet();
  }

  test('v19 drops repayment_schedule triggers and purges its tombstones', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    await DatabaseMigrations.run(db, 16, 17);
    // Simulate the pre-v19 state: repayment_schedule was change-tracked.
    await db.execute(
        "CREATE TRIGGER trg_repayment_schedule_ins AFTER INSERT ON repayment_schedule "
        "BEGIN UPDATE repayment_schedule SET updated_at = "
        "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END");
    await db.execute(
        "CREATE TRIGGER trg_repayment_schedule_upd AFTER UPDATE ON repayment_schedule "
        "BEGIN UPDATE repayment_schedule SET updated_at = "
        "strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id; END");
    await db.execute(
        "CREATE TRIGGER trg_repayment_schedule_del AFTER DELETE ON repayment_schedule "
        "BEGIN INSERT INTO sync_tombstones (deleted_table, deleted_row_id, deleted_at) "
        "VALUES ('repayment_schedule', OLD.id, "
        "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')); END");
    await db.insert('sync_tombstones', {
      'deleted_table': 'repayment_schedule',
      'deleted_row_id': 'S1',
      'deleted_at': '2026-08-04T10:00:00.000Z',
    });

    expect(await triggerNames(db), contains('trg_repayment_schedule_ins'));

    await DatabaseMigrations.run(db, 18, 19);

    final triggers = await triggerNames(db);
    expect(triggers, isNot(contains('trg_repayment_schedule_ins')));
    expect(triggers, isNot(contains('trg_repayment_schedule_upd')));
    expect(triggers, isNot(contains('trg_repayment_schedule_del')));
    // Every other table keeps its change tracking.
    expect(triggers, contains('trg_customers_ins'));
    expect(triggers, contains('trg_customers_upd'));
    expect(triggers, contains('trg_customers_del'));
    // The stale repayment_schedule tombstone is purged.
    final tombstones = await db.query('sync_tombstones');
    expect(tombstones, isEmpty);
  });

  test('fresh installs never create repayment_schedule triggers', () async {
    final db = await openV16Database();
    addTearDown(db.close);

    // v17 with the current createSyncSchema must not create repayment_schedule
    // tracking (it was removed from the change-tracked table list in v19).
    await DatabaseMigrations.run(db, 16, 17);

    final triggers = await triggerNames(db);
    expect(triggers, isNot(contains('trg_repayment_schedule_ins')));
    expect(triggers, isNot(contains('trg_repayment_schedule_upd')));
    expect(triggers, isNot(contains('trg_repayment_schedule_del')));
    expect(triggers, contains('trg_loans_ins'));
  });
}
