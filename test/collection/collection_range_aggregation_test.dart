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

  /// Seeds one customer + a 2-installment loan with installments due on
  /// 2026-08-03 and 2026-08-04.
  Future<void> seedTwoInstallmentLoan(Database db) async {
    await db.insert('customers', {'id': 'C1', 'full_name': 'Ada', 'phone': '080'});
    final start = DateTime(2026, 8, 3);
    final loan = Loan(
      id: 'L1',
      customerId: 'C1',
      loanType: LoanType.daily,
      amount: 2000,
      interestRate: 0,
      duration: 2,
      loanDate: start,
      repaymentStartDate: start,
      totalRepayment: 2000,
      outstandingBalance: 2000,
      installmentAmount: 1000,
      expectedCompletionDate: DateTime(2026, 8, 5),
    );
    final amounts = CurrencyUtils.splitEvenly(2000, 2);
    final schedule = ScheduleGenerator.generate(
      loanId: 'L1',
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
      'range collection does NOT multiply amountPaid by the number of '
      'in-range installments (cartesian-product guard)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedTwoInstallmentLoan(db);

    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 1000,
      'status': 'completed',
      'payment_date': '2026-08-03',
    });

    final result = await repo(db).getCollectionsByDateRange(
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
    );
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        // One payment must stay 1000 — a join against the two in-range
        // schedule rows used to inflate it to 2000.
        expect(rows.first.amountPaid, closeTo(1000.0, 0.001));
        // Both installments remain due (paid_amount untouched).
        expect(rows.first.amountDue, closeTo(2000.0, 0.001));
        expect(rows.first.installmentAmount, closeTo(1000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'range collection amountPaid subtracts overpayments credited to savings '
      '(money rule)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedTwoInstallmentLoan(db);

    // Overpay one installment: 1500 paid, 500 credited to savings.
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 1500,
      'status': 'completed',
      'payment_date': '2026-08-03',
    });
    await db.insert('savings_transactions', {
      'id': 'ST1',
      'customer_id': 'C1',
      'amount': 500,
      'type': 'overpayment',
      'reference_loan_payment_id': 'P1',
      'created_at': '2026-08-03T10:00:00.000Z',
    });

    final result = await repo(db).getCollectionsByDateRange(
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
    );
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        // Collected = 1500 - 500 overpayment = 1000, never the gross 1500.
        expect(rows.first.amountPaid, closeTo(1000.0, 0.001));
        expect(rows.first.amountDue, closeTo(2000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('reversed payments are excluded from range amountPaid', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedTwoInstallmentLoan(db);

    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 1000,
      'status': 'reversed',
      'payment_date': '2026-08-03',
    });

    final result = await repo(db).getCollectionsByDateRange(
      DateTime(2026, 8, 3),
      DateTime(2026, 8, 4),
    );
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(0.0, 0.001));
        expect(rows.first.amountDue, closeTo(2000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}
