import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/loan_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Exercises `regenSchedulesForActiveLoans` against a real (in-memory)
/// SQLite engine so the holiday honoring is verified against actual stored
/// `due_date` rows:
///  * loans with paid installments keep every non-pending row untouched and
///    only re-date the pending tail, skipping the new holiday
///  * payment-free loans still get the full regeneration
///  * fully-paid loans are skipped
class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());

  final Database _db;

  @override
  Future<Database> get database async => _db;
}

void main() {
  sqfliteFfiInit();

  Future<Database> openDb() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_type TEXT NOT NULL,
        status TEXT NOT NULL,
        amount REAL NOT NULL,
        interest_rate REAL NOT NULL,
        duration_days INTEGER,
        duration_weeks INTEGER,
        start_date TEXT NOT NULL,
        total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL,
        custom_collection_amount REAL
      )
    ''');
    await db.execute('''
      CREATE TABLE repayment_schedule (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL,
        paid_amount REAL NOT NULL
      )
    ''');
    return db;
  }

  Future<List<Map<String, Object?>>> scheduleRows(Database db, String loanId) {
    return db.query('repayment_schedule',
        where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'installment_number ASC');
  }

  // Monday 2026-08-17 is a holiday.
  final holiday = Holiday(
    id: 'H1',
    name: 'Public Holiday',
    date: DateTime(2026, 8, 17),
  );

  test(
      'partially paid loan keeps paid installments and re-dates only the pending tail',
      () async {
    final db = await openDb();
    addTearDown(db.close);

    await db.insert('loans', {
      'id': 'L1',
      'customer_id': 'C1',
      'loan_type': 'weekly',
      'status': 'active',
      'amount': 4000.0,
      'interest_rate': 10.0,
      'duration_weeks': 4,
      'start_date': '2026-08-03',
      'total_repayment': 4000.0,
      'outstanding_balance': 2000.0,
    });
    // Installments 1–2 paid (Aug 3, Aug 10); 3–4 pending (Aug 17, Aug 24).
    await db.insert('repayment_schedule', {
      'id': 'S1',
      'loan_id': 'L1',
      'installment_number': 1,
      'due_date': '2026-08-03',
      'amount': 1000.0,
      'status': 'paid',
      'paid_amount': 1000.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S2',
      'loan_id': 'L1',
      'installment_number': 2,
      'due_date': '2026-08-10',
      'amount': 1000.0,
      'status': 'paid',
      'paid_amount': 1000.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S3',
      'loan_id': 'L1',
      'installment_number': 3,
      'due_date': '2026-08-17',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S4',
      'loan_id': 'L1',
      'installment_number': 4,
      'due_date': '2026-08-24',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });

    final repo = LoanRepository(_FakeDatabaseService(db));
    final result = await repo.regenSchedulesForActiveLoans([holiday]);

    result.when(
      success: (count) => expect(count, 1),
      failure: (f) => fail('regen failed: $f'),
    );

    final schedule = await scheduleRows(db, 'L1');
    expect(schedule.length, 4);
    // Paid installments preserved exactly.
    expect(schedule[0]['due_date'], '2026-08-03');
    expect(schedule[1]['due_date'], '2026-08-10');
    expect(schedule[0]['status'], 'paid');
    expect(schedule[0]['paid_amount'], 1000.0);
    expect(schedule[0]['amount'], 1000.0);
    // Pending tail shifted past the holiday, amounts preserved.
    expect(schedule[2]['due_date'], '2026-08-18'); // Aug 17 holiday → Tue 18
    expect(schedule[3]['due_date'], '2026-08-25'); // continues from the kept tail
    expect(schedule[2]['amount'], 1000.0);
    expect(schedule[3]['amount'], 1000.0);
    expect(schedule[2]['status'], 'pending');
  });

  test('payment-free loans still get the full regeneration', () async {
    final db = await openDb();
    addTearDown(db.close);

    // Daily loan starting exactly on the holiday Monday.
    await db.insert('loans', {
      'id': 'L2',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 3000.0,
      'interest_rate': 10.0,
      'duration_days': 3,
      'start_date': '2026-08-17',
      'total_repayment': 3000.0,
      'outstanding_balance': 3000.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S1',
      'loan_id': 'L2',
      'installment_number': 1,
      'due_date': '2026-08-17',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S2',
      'loan_id': 'L2',
      'installment_number': 2,
      'due_date': '2026-08-18',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S3',
      'loan_id': 'L2',
      'installment_number': 3,
      'due_date': '2026-08-19',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });

    final repo = LoanRepository(_FakeDatabaseService(db));
    final result = await repo.regenSchedulesForActiveLoans([holiday]);

    result.when(
      success: (count) => expect(count, 1),
      failure: (f) => fail('regen failed: $f'),
    );

    final schedule = await scheduleRows(db, 'L2');
    expect(schedule.length, 3);
    // All pending installments shift past the holiday Monday.
    expect(schedule[0]['due_date'], '2026-08-18');
    expect(schedule[1]['due_date'], '2026-08-19');
    expect(schedule[2]['due_date'], '2026-08-20');
  });

  test('fully paid loans are skipped', () async {
    final db = await openDb();
    addTearDown(db.close);

    await db.insert('loans', {
      'id': 'L3',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 1000.0,
      'interest_rate': 10.0,
      'duration_days': 1,
      'start_date': '2026-08-14',
      'total_repayment': 1000.0,
      'outstanding_balance': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'S1',
      'loan_id': 'L3',
      'installment_number': 1,
      'due_date': '2026-08-14',
      'amount': 1000.0,
      'status': 'paid',
      'paid_amount': 1000.0,
    });

    final repo = LoanRepository(_FakeDatabaseService(db));
    final result = await repo.regenSchedulesForActiveLoans([holiday]);

    result.when(
      success: (count) => expect(count, 0),
      failure: (f) => fail('regen failed: $f'),
    );

    final schedule = await scheduleRows(db, 'L3');
    expect(schedule.length, 1);
    expect(schedule[0]['due_date'], '2026-08-14');
    expect(schedule[0]['status'], 'paid');
  });
}
