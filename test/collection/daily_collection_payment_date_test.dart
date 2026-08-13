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

  Future<void> seedLoan(Database db) async {
    await db.insert('customers', {
      'id': 'C1',
      'full_name': 'Ada',
      'phone': '080',
    });
    final loan = Loan(
      id: 'L1',
      customerId: 'C1',
      loanType: LoanType.daily,
      amount: 5000,
      interestRate: 0,
      duration: 5,
      loanDate: DateTime(2026, 8, 1),
      repaymentStartDate: DateTime(2026, 8, 3),
      totalRepayment: 5000,
      outstandingBalance: 5000,
      installmentAmount: 1000,
      expectedCompletionDate: DateTime(2026, 8, 7),
    );
    final amounts = CurrencyUtils.splitEvenly(5000, 5);
    final schedule = ScheduleGenerator.generate(
      loanId: 'L1',
      loanType: LoanType.daily,
      startDate: DateTime(2026, 8, 3),
      amounts: amounts,
      holidays: const [],
    );
    await db.insert('loans', loan.toMap());
    for (final inst in schedule) {
      await db.insert('repayment_schedule', inst.toMap());
    }
  }

  Future<void> insertPayment(
    Database db,
    String id,
    double amount,
    String date, {
    String status = 'completed',
  }) async {
    await db.insert('payments', {
      'id': id,
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': amount,
      'status': status,
      'payment_date': date,
    });
  }

  CollectionRepository repo(Database db) =>
      CollectionRepository(_FakeDatabaseService(db));

  test(
      'a payment received on the viewed date shows as collected even when it '
      'cleared an earlier installment', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db); // installments Mon 08-03 .. Fri 08-07

    // Ada pays on Wed 08-05; the money is applied to the oldest missed
    // installment, so her Wed installment itself may still be unpaid.
    await insertPayment(db, 'P1', 1000, '2026-08-05');

    final result = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        // amountPaid follows the PAYMENT DATE, not the installment it cleared.
        expect(row.amountPaid, closeTo(1000.0, 0.001));
        expect(row.amountDue, closeTo(1000.0, 0.001));
        // The day's own installment is untouched by today's role as allocator.
        expect(row.scheduleStatus, 'pending');
        expect(row.schedulePaidAmount, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('payment on a date with no installment still lists the loan as collected',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db); // last installment Fri 08-07

    // Ada pays up on Mon 08-10 when no installment is due that day.
    await insertPayment(db, 'P1', 5000, '2026-08-10');

    final result = await repo(db).getDailyCollection(DateTime(2026, 8, 10));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.amountDue, closeTo(0.0, 0.001));
        expect(row.amountPaid, closeTo(5000.0, 0.001));
        expect(row.scheduleStatus, 'pending');
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('payment received on another day does NOT count on the viewed date',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db);

    await insertPayment(db, 'P1', 1000, '2026-08-05');

    // 08-06 has its own installment due; no money was physically received on
    // 08-06, so the loan still reads as owing even though Ada paid yesterday.
    final result = await repo(db).getDailyCollection(DateTime(2026, 8, 6));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.amountDue, closeTo(1000.0, 0.001));
        expect(row.amountPaid, closeTo(0.0, 0.001));
        expect(row.isPaid, isFalse);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('daily amountPaid subtracts overpayment surplus (money rule)',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db);

    // 1500 received on 08-05, of which 500 went to savings as an overpayment.
    await insertPayment(db, 'P1', 1500, '2026-08-05');
    await db.insert('savings_transactions', {
      'id': 'S1',
      'customer_id': 'C1',
      'amount': 500,
      'type': 'overpayment',
      'reference_loan_payment_id': 'P1',
      'created_at': '2026-08-05T10:00:00.000Z',
    });

    final result = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(1000.0, 0.001));
        expect(rows.first.scheduleStatus, 'pending');
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('reversed payment does not mark the viewed date as paid', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedLoan(db);

    await insertPayment(db, 'P1', 1000, '2026-08-05', status: 'reversed');

    final result = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    result.when(
      success: (rows) {
        // Row appears because 08-05 has a scheduled installment; the reversed
        // payment contributes nothing.
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.amountPaid, closeTo(0.0, 0.001));
        expect(row.isPaid, isFalse);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}