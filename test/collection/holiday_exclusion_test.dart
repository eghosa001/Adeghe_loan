import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

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
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        phone TEXT,
        group_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_type TEXT NOT NULL,
        amount REAL NOT NULL,
        interest_rate REAL NOT NULL,
        insurance_fee REAL DEFAULT 0.0,
        commission REAL DEFAULT 0.0,
        processing_fee REAL DEFAULT 0.0,
        admin_fee REAL DEFAULT 0.0,
        other_charges REAL DEFAULT 0.0,
        loan_date TEXT NOT NULL,
        start_date TEXT NOT NULL,
        duration_days INTEGER,
        duration_weeks INTEGER,
        repayment_frequency TEXT,
        daily_payment REAL,
        weekly_payment REAL,
        total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL,
        expected_completion_date TEXT NOT NULL,
        custom_collection_amount REAL,
        collector TEXT,
        notes TEXT,
        status TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE repayment_schedule (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        paid_amount REAL NOT NULL DEFAULT 0.0
      )
    ''');
    await db.execute('''
      CREATE TABLE customer_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
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
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL,
        payment_date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        reference_loan_payment_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    return db;
  }

  Future<void> seedLoan(Database db, String loanId, DateTime start) async {
    await db.insert('customers', {'id': 'C1', 'full_name': 'Ada', 'phone': '080'});
    final loan = Loan(
      id: loanId,
      customerId: 'C1',
      loanType: LoanType.daily,
      amount: 5000,
      interestRate: 0,
      duration: 5,
      loanDate: start,
      repaymentStartDate: start,
      totalRepayment: 5000,
      outstandingBalance: 5000,
      installmentAmount: 1000,
      expectedCompletionDate: DateTime(2026, 8, 7),
    );
    final amounts = CurrencyUtils.splitEvenly(5000, 5);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId,
      loanType: LoanType.daily,
      startDate: start,
      amounts: amounts,
      holidays: const [],
    );
    await db.insert('loans', loan.toMap());
    for (final inst in schedule) {
      await db.insert('repayment_schedule', inst.toMap());
    }
  }

  CollectionRepository repo(Database db) =>
      CollectionRepository(_FakeDatabaseService(db));

  test(
      'daily collection is empty on a one-time holiday even when the schedule '
      'still has an installment there (stale pre-holiday schedule)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db, 'L1', DateTime(2026, 8, 3)); // Mon–Fri installments

    // A schedule row already exists on Wed 2026-08-05; the holiday is created
    // after the schedule (no regen simulated).
    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Midweek',
      'date': '2026-08-05',
      'is_recurring': 0,
      'is_enabled': 1,
    });

    final holidayRows = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    holidayRows.when(
      success: (rows) => expect(rows, isEmpty,
          reason: 'collection sheet must skip a one-time holiday'),
      failure: (f) => fail('query failed: $f'),
    );

    // Non-holiday dates still collect.
    final normalRows = await repo(db).getDailyCollection(DateTime(2026, 8, 6));
    normalRows.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountDue, 1000.0);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('recurring holiday excludes the same month/day every year', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db, 'L1', DateTime(2026, 8, 3));

    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Remembrance',
      'date': '2026-08-06',
      'is_recurring': 1,
      'is_enabled': 1,
    });

    // 2026-08-06 is a recurring holiday date.
    final rows = await repo(db).getDailyCollection(DateTime(2026, 8, 6));
    rows.when(
      success: (r) => expect(r, isEmpty,
          reason: 'recurring holiday month/day must be skipped'),
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('disabled holidays are not excluded', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db, 'L1', DateTime(2026, 8, 3));

    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Disabled',
      'date': '2026-08-05',
      'is_recurring': 0,
      'is_enabled': 0,
    });

    final rows = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    rows.when(
      success: (r) {
        expect(r, hasLength(1));
        expect(r.first.amountDue, 1000.0);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('date range collection excludes holiday installments', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db, 'L1', DateTime(2026, 8, 3));

    await db.insert('holidays', {
      'id': 'H1',
      'name': 'Midweek',
      'date': '2026-08-05',
      'is_recurring': 0,
      'is_enabled': 1,
    });

    // Range covers the whole week: 5 installments, minus the holiday = 4.
    final result = await repo(db).getCollectionsByDateRange(
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 7),
    );
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountDue, closeTo(4000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}
