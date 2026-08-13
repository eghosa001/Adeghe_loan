import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Validates the v24 `payments.created_at` migration.
///
/// `getPaymentsForLoan` has always ordered by `payment_date DESC,
/// created_at DESC`, but the `payments` table never actually had a
/// `created_at` column (fresh DDL, migrations, and the cloud mirror all lacked
/// it), so loading a loan's payment history threw
/// `no such column: created_at` on every real database. v24 adds the column
/// and back-fills existing rows so the same-day tie-break is stable.
void main() {
  sqfliteFfiInit();

  Future<Database> openV23Database() async {
    final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath, options: OpenDatabaseOptions(version: 23));
    for (final create in [
      'CREATE TABLE payments ('
      ' id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, customer_id TEXT NOT NULL, '
      ' amount REAL NOT NULL, payment_date TEXT NOT NULL, payment_method TEXT NOT NULL, '
      ' reference_no TEXT, receipt_no TEXT UNIQUE NOT NULL, collector TEXT NOT NULL, '
      ' remarks TEXT, type TEXT DEFAULT \'partial\', '
      " status TEXT NOT NULL DEFAULT 'completed', prior_loan_status TEXT, "
      ' client_request_id TEXT, updated_at TEXT)',
    ]) {
      await db.execute(create);
    }
    return db;
  }

  test('v24 adds created_at and back-fills existing payments', () async {
    final db = await openV23Database();
    addTearDown(db.close);

    await db.insert('payments', {
      'id': 'P1', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 5000.0,
      'payment_date': '2026-08-01', 'payment_method': 'cash',
      'receipt_no': 'REC-A', 'collector': 'Admin', 'status': 'completed',
      'updated_at': '2026-08-01T10:00:00.000Z',
    });
    await db.insert('payments', {
      'id': 'P2', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 2000.0,
      'payment_date': '2026-08-03', 'payment_method': 'cash',
      'receipt_no': 'REC-B', 'collector': 'Admin', 'status': 'completed',
      'updated_at': null,
    });

    await DatabaseMigrations.run(db, 23, 24);

    final rows = await db.query('payments', orderBy: 'id ASC');
    expect(rows, hasLength(2));
    expect(rows[0]['created_at'], '2026-08-01T10:00:00.000Z',
        reason: 'row with updated_at must be back-filled from it');
    expect(rows[1]['created_at'], '2026-08-03T00:00:00.000Z',
        reason: 'row without updated_at falls back to its payment date');
    expect(rows[0]['payment_date'], '2026-08-01',
        reason: 'back-fill must not touch the payment date itself');
  });

  test('v24 does not rewrite rows that already have created_at', () async {
    final db = await openV23Database();
    addTearDown(db.close);

    // Simulate a build that shipped the fresh DDL with created_at while the
    // version constant was still 23 (same guard pattern as v18).
    await db.execute('ALTER TABLE payments ADD COLUMN created_at TEXT');
    await db.insert('payments', {
      'id': 'P1', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 5000.0,
      'payment_date': '2026-08-01', 'payment_method': 'cash',
      'receipt_no': 'REC-A', 'collector': 'Admin', 'status': 'completed',
      'created_at': '2026-08-01T10:00:00.000Z',
    });

    await DatabaseMigrations.run(db, 23, 24);

    final rows = await db.query('payments');
    expect(rows.single['created_at'], '2026-08-01T10:00:00.000Z',
        reason: 'existing created_at must be preserved');
  });

  test('v24 leaves the ordering query valid (regression for the crash)',
      () async {
    final db = await openV23Database();
    addTearDown(db.close);
    await db.insert('payments', {
      'id': 'P1', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 5000.0,
      'payment_date': '2026-08-01', 'payment_method': 'cash',
      'receipt_no': 'REC-A', 'collector': 'Admin', 'status': 'completed',
    });

    await DatabaseMigrations.run(db, 23, 24);

    // The exact query `getPaymentsForLoan` issues. Before v24 this threw
    // `no such column: created_at`.
    final rows = await db.query(
      'payments',
      where: 'loan_id = ?',
      whereArgs: ['L1'],
      orderBy: 'payment_date DESC, created_at DESC',
    );
    expect(rows, hasLength(1));
  });
}
