import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Exercises the derived-schedule rebuild (`LoanScheduleService`) against a
/// real (in-memory) SQLite engine so the holiday honoring and payment
/// allocation are verified against actual stored rows:
///  * `rebuildAllSchedules` fully regenerates every loan's schedule as a pure
///    function of (loan + holidays), shifting due dates past the new holiday
///  * paid/partial/pending statuses are re-allocated chronologically from the
///    completed payments, with the overpayment surplus excluded
///  * `rebuildSchedule` on a missing loan is a no-op that still bumps nothing
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
    await db.execute('''
      CREATE TABLE holidays (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        date TEXT NOT NULL,
        is_recurring INTEGER NOT NULL,
        is_enabled INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        status TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        reference_loan_payment_id TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL
      )
    ''');
    return db;
  }

  Future<List<Map<String, Object?>>> scheduleRows(Database db, String loanId) {
    return db.query('repayment_schedule',
        where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'installment_number ASC');
  }

  // Monday 2026-08-17 is a holiday.
  const holidayDate = '2026-08-17';

  test('rebuildAllSchedules fully regenerates and shifts due dates past a '
      'new holiday (payment-free loan)', () async {
    final db = await openDb();
    addTearDown(db.close);

    await db.insert('loans', {
      'id': 'L1',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 3000.0,
      'interest_rate': 10.0,
      'duration_days': 3,
      'start_date': holidayDate,
      'total_repayment': 3000.0,
      'outstanding_balance': 3000.0,
    });
    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Public Holiday',
      'date': holidayDate,
      'is_recurring': 0,
      'is_enabled': 1,
    });
    // Stale pre-holiday schedule (as if generated before the holiday existed).
    await db.insert('repayment_schedule', {
      'id': 'L1-1',
      'loan_id': 'L1',
      'installment_number': 1,
      'due_date': holidayDate,
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'L1-2',
      'loan_id': 'L1',
      'installment_number': 2,
      'due_date': '2026-08-18',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });
    await db.insert('repayment_schedule', {
      'id': 'L1-3',
      'loan_id': 'L1',
      'installment_number': 3,
      'due_date': '2026-08-19',
      'amount': 1000.0,
      'status': 'pending',
      'paid_amount': 0.0,
    });

    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());
    await service.rebuildAllSchedules();

    final schedule = await scheduleRows(db, 'L1');
    expect(schedule.length, 3);
    // All pending installments shift past the holiday Monday.
    expect(schedule[0]['due_date'], '2026-08-18');
    expect(schedule[1]['due_date'], '2026-08-19');
    expect(schedule[2]['due_date'], '2026-08-20');
    // Deterministic ids.
    expect(schedule.map((s) => s['id']), ['L1-1', 'L1-2', 'L1-3']);
    expect(schedule.every((s) => s['status'] == 'pending'), isTrue);
    expect(schedule.every((s) => s['paid_amount'] == 0.0), isTrue);
  });

  test('rebuild allocates paid/partial/pending from completed payments, '
      'excluding the overpayment surplus (money rule)', () async {
    final db = await openDb();
    addTearDown(db.close);

    // Weekly loan, 4 x 1000 = 4000. Two payments: 1000 fully on installment 1,
    // then 1500 against installment 2 — 1000 to the loan + 500 overpayment
    // surplus credited to savings (never applied to the loan).
    await db.insert('loans', {
      'id': 'L2',
      'customer_id': 'C1',
      'loan_type': 'weekly',
      'status': 'active',
      'amount': 4000.0,
      'interest_rate': 10.0,
      'duration_weeks': 4,
      'start_date': '2026-08-03',
      'total_repayment': 4000.0,
      'outstanding_balance': 2500.0,
    });
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L2',
      'status': 'completed',
      'amount': 1000.0,
    });
    await db.insert('payments', {
      'id': 'P2',
      'loan_id': 'L2',
      'status': 'completed',
      'amount': 1500.0,
    });
    await db.insert('savings_transactions', {
      'id': 'ST1',
      'reference_loan_payment_id': 'P2',
      'type': 'overpayment',
      'amount': 500.0,
    });

    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());
    await service.rebuildAllSchedules();

    final schedule = await scheduleRows(db, 'L2');
    expect(schedule.length, 4);
    // 2000 applied to the loan: installment 1 paid, installment 2 fully paid.
    expect(schedule[0]['status'], 'paid');
    expect(schedule[0]['paid_amount'], 1000.0);
    expect(schedule[1]['status'], 'paid');
    expect(schedule[1]['paid_amount'], 1000.0);
    expect(schedule[2]['status'], 'pending');
    expect(schedule[2]['paid_amount'], 0.0);
    expect(schedule[3]['status'], 'pending');
  });

  test('rebuild marks installments partial for a fractional application', () async {
    final db = await openDb();
    addTearDown(db.close);

    // 3 x 1000 = 3000; one payment of 500 applies only to the first installment.
    await db.insert('loans', {
      'id': 'L3',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 3000.0,
      'interest_rate': 10.0,
      'duration_days': 3,
      'start_date': '2026-08-03',
      'total_repayment': 3000.0,
      'outstanding_balance': 2500.0,
    });
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L3',
      'status': 'completed',
      'amount': 500.0,
    });

    final service = LoanScheduleService(
        _FakeDatabaseService(db), LoanScheduleVersionNotifier());
    await service.rebuildAllSchedules();

    final schedule = await scheduleRows(db, 'L3');
    expect(schedule[0]['status'], 'partial');
    expect(schedule[0]['paid_amount'], 500.0);
    expect(schedule[1]['status'], 'pending');
    expect(schedule[2]['status'], 'pending');
  });

  test('rebuildSchedule on a missing loan is a no-op', () async {
    final db = await openDb();
    addTearDown(db.close);

    final notifier = LoanScheduleVersionNotifier();
    final service = LoanScheduleService(_FakeDatabaseService(db), notifier);

    await service.rebuildSchedule('does-not-exist');

    expect(notifier.state, 0);
    expect(await db.query('repayment_schedule'), isEmpty);
  });

  test('version notifier bumps after a successful rebuild', () async {
    final db = await openDb();
    addTearDown(db.close);

    await db.insert('loans', {
      'id': 'L4',
      'customer_id': 'C1',
      'loan_type': 'daily',
      'status': 'active',
      'amount': 1000.0,
      'interest_rate': 10.0,
      'duration_days': 1,
      'start_date': '2026-08-03',
      'total_repayment': 1000.0,
      'outstanding_balance': 1000.0,
    });

    final notifier = LoanScheduleVersionNotifier();
    final service = LoanScheduleService(_FakeDatabaseService(db), notifier);

    await service.rebuildSchedule('L4');
    expect(notifier.state, 1);

    await service.rebuildAllSchedules();
    expect(notifier.state, 2);
  });
}
