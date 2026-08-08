import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/reports/data/report_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Guards the savings date-bucketing fix: `savings_transactions.created_at` is
/// a LOCAL ISO-8601 string (`DateTime.now().toIso8601String()`, no timezone
/// suffix) written by Dart, so SQLite's `DATE(created_at)` interprets it as UTC
/// and buckets a transaction recorded 00:00–00:59 local (Nigeria is UTC+1) onto
/// the PREVIOUS day. The dashboard savings buckets must use the stored local
/// day (`substr(created_at, 1, 10)`) instead.
void main() {
  sqfliteFfiInit();

  Future<Database> createSchema() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT,
        amount REAL,
        status TEXT,
        loan_date TEXT,
        outstanding_balance REAL,
        loan_type TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT,
        amount REAL,
        status TEXT,
        payment_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        reference_loan_payment_id TEXT,
        type TEXT,
        amount REAL,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        status TEXT,
        date_registered TEXT
      )
    ''');
    return db;
  }

  test('savings recorded 00:00-00:59 local bucket on the local day', () async {
    final db = await createSchema();
    addTearDown(db.close);
    final service = DatabaseService.withOpenOverride(
        SecureStorageService(), () async => db);
    addTearDown(service.close);

    // Both rows carry local timestamps in the first hour of 05 Aug. Under
    // DATE(created_at) (UTC interpretation) they would land on 04 Aug and be
    // missed by a 05 Aug range.
    await db.insert('savings_transactions', {
      'id': 't1',
      'type': 'deposit',
      'amount': 100.0,
      'created_at': '2026-08-05T00:30:00.000',
    });
    await db.insert('savings_transactions', {
      'id': 't2',
      'type': 'withdrawal',
      'amount': 40.0,
      'created_at': '2026-08-05T00:59:59.000',
    });

    final repo = ReportRepository(service);
    final result = await repo.getDashboardTrends(
      startDate: DateTime(2026, 8, 5),
      endDate: DateTime(2026, 8, 5),
    );

    final trends = result.dataOrNull;
    expect(trends, isNotNull, reason: 'expected a successful trends result');
    expect(trends!.savingsIn, hasLength(1));
    expect(trends.savingsIn.single.value, 100.0);
    expect(trends.savingsOut.single.value, 40.0);
  });
}
