import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Validates the v23 `updated_at` backfill: a row inserted by a path where the
/// v17 stamp trigger never ran keeps a NULL `updated_at`, is pushed as explicit
/// NULL, and is then rejected by the other device's pull guard
/// (`isSaneCloudRow` requires a valid sync timestamp) — so that payment/savings
/// row never reaches the other device and its totals differ forever. v23 stamps
/// every NULL row in the replicated tables with a valid `syncTimestamp()` so
/// the next push sends a pullable row.
void main() {
  sqfliteFfiInit();

  final timestampPattern =
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

  Future<Database> openV22Database() async {
    final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath, options: OpenDatabaseOptions(version: 22));
    for (final create in [
      'CREATE TABLE business_profile (id TEXT PRIMARY KEY, updated_at TEXT)',
      'CREATE TABLE customer_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, updated_at TEXT)',
      '''CREATE TABLE customers (
           id TEXT PRIMARY KEY, full_name TEXT NOT NULL, phone TEXT NOT NULL,
           date_registered TEXT NOT NULL, status TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE loans (
           id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, amount REAL NOT NULL,
           loan_type TEXT NOT NULL, status TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE payments (
           id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, customer_id TEXT NOT NULL,
           amount REAL NOT NULL, status TEXT NOT NULL, type TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE savings_accounts (
           id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, balance REAL NOT NULL,
           created_at TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE savings_transactions (
           id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, type TEXT NOT NULL,
           amount REAL NOT NULL, created_at TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE documents (
           id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, file_path TEXT NOT NULL,
           mime_type TEXT NOT NULL, updated_at TEXT)''',
      '''CREATE TABLE holidays (
           id TEXT PRIMARY KEY, date TEXT NOT NULL, name TEXT NOT NULL,
           updated_at TEXT)''',
    ]) {
      await db.execute(create);
    }
    return db;
  }

  Future<void> seedNullRows(Database db) async {
    await db.insert('customers', {
      'id': 'C1', 'full_name': 'NULL TARGET', 'phone': '0801',
      'date_registered': '2026-01-01', 'status': 'active', 'updated_at': null,
    });
    await db.insert('payments', {
      'id': 'P1', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 5000.0,
      'status': 'completed', 'type': 'partial', 'updated_at': null,
    });
    await db.insert('savings_transactions', {
      'id': 'S1', 'customer_id': 'C1', 'type': 'deposit', 'amount': 500.0,
      'created_at': '2026-01-01T00:00:00.000Z', 'updated_at': null,
    });
    await db.insert('holidays', {
      'id': 'H1', 'date': '2026-12-25', 'name': 'Christmas', 'updated_at': null,
    });
  }

  test('v23 stamps every NULL updated_at with a valid sync timestamp',
      () async {
    final db = await openV22Database();
    addTearDown(db.close);
    await seedNullRows(db);

    await DatabaseMigrations.run(db, 22, 23);

    for (final table in const [
      'business_profile', 'customer_groups', 'customers', 'loans', 'payments',
      'savings_accounts', 'savings_transactions', 'documents', 'holidays',
    ]) {
      final rows = await db.query(table, columns: ['updated_at']);
      for (final row in rows) {
        final stamp = row['updated_at'] as String?;
        expect(stamp, isNotNull,
            reason: 'v23 left a NULL updated_at in $table');
        expect(stamp, matches(timestampPattern),
            reason: 'v23 wrote a malformed timestamp in $table: $stamp');
      }
    }
  });

  test('v23 does not rewrite rows that already have a timestamp', () async {
    final db = await openV22Database();
    addTearDown(db.close);
    await db.insert('customers', {
      'id': 'C1', 'full_name': 'KEPT', 'phone': '0801',
      'date_registered': '2026-01-01', 'status': 'active',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });

    await DatabaseMigrations.run(db, 22, 23);

    final rows = await db.query('customers', columns: ['updated_at']);
    expect(rows.single['updated_at'], '2026-01-01T00:00:00.000Z',
        reason: 'v23 must only touch NULL rows');
  });
}
