import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';
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
        group_id TEXT,
        guarantor_1_name TEXT,
        guarantor_1_phone TEXT
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
    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    return db;
  }

  Future<void> seedWeeklyLoan(
    Database db,
    String loanId,
    String customerId,
    String name, {
    LoanStatus status = LoanStatus.active,
    double amount = 2000,
    double interestRate = 10,
    DateTime? startDate,
    double? charge,
    double outstandingBalance = 2000,
    double installmentAmount = 550,
    int duration = 4,
  }) async {
    final start = startDate ?? DateTime(2026, 8, 5); // Wednesday
    await db.insert('customers', {
      'id': customerId,
      'full_name': name,
      'phone': '0801',
      'guarantor_1_name': 'Grace',
      'guarantor_1_phone': '0802',
    });
    final totalRepayment = amount +
        (amount * interestRate / 100) +
        (charge ?? 0);
    final loan = Loan(
      id: loanId,
      customerId: customerId,
      loanType: LoanType.weekly,
      status: status,
      amount: amount,
      interestRate: interestRate,
      otherCharges: charge ?? 0,
      duration: duration,
      loanDate: DateTime(2026, 8, 1),
      repaymentStartDate: start,
      totalRepayment: totalRepayment,
      outstandingBalance: outstandingBalance,
      installmentAmount: installmentAmount,
      expectedCompletionDate: DateTime(2026, 9, 1),
    );
    final amounts = CurrencyUtils.splitEvenly(totalRepayment, duration);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId,
      loanType: LoanType.weekly,
      startDate: start,
      amounts: amounts,
      holidays: const [],
    );
    await db.insert('loans', loan.toMap());
    for (final inst in schedule) {
      await db.insert('repayment_schedule', inst.toMap());
    }
  }

  Future<void> seedDailyLoan(Database db) async {
    await db.insert('customers', {
      'id': 'C9',
      'full_name': 'DailyOnly',
      'phone': '0809',
    });
    final loan = Loan(
      id: 'L9',
      customerId: 'C9',
      loanType: LoanType.daily,
      status: LoanStatus.active,
      amount: 1000,
      interestRate: 0,
      duration: 3,
      loanDate: DateTime(2026, 8, 1),
      repaymentStartDate: DateTime(2026, 8, 3),
      totalRepayment: 1000,
      outstandingBalance: 1000,
      installmentAmount: 1000 / 3,
      expectedCompletionDate: DateTime(2026, 8, 6),
    );
    await db.insert('loans', loan.toMap());
  }

  CollectionRepository repo(Database db) =>
      CollectionRepository(_FakeDatabaseService(db));

  test('returns only active weekly loans (excludes daily and non-active)',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada Weekly');
    await seedWeeklyLoan(db, 'L2', 'C2', 'Beta Done',
        status: LoanStatus.completed, outstandingBalance: 0);
    await seedWeeklyLoan(db, 'L3', 'C3', 'Gamma Cancelled',
        status: LoanStatus.cancelled);
    await seedDailyLoan(db);

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        // Completed loans should now appear (to show as "paid" with green tick)
        // Cancelled loans should still be excluded
        expect(rows, hasLength(2));
        final names = rows.map((r) => r.customerName).toList();
        expect(names, contains('Ada Weekly'));
        expect(names, contains('Beta Done'));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('amountPaid follows the money rule: completed minus overpayments',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada');

    // 550 loan-applied payment.
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-08-06',
    });
    // 700 payment of which 150 went to savings as an overpayment → 550 applied.
    await db.insert('payments', {
      'id': 'P2',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 700,
      'status': 'completed',
      'payment_date': '2026-08-06',
    });
    await db.insert('savings_transactions', {
      'id': 'S1',
      'customer_id': 'C1',
      'amount': 150,
      'type': 'overpayment',
      'reference_loan_payment_id': 'P2',
      'created_at': '2026-08-06T10:00:00.000Z',
    });
    // Reversed payment must never count.
    await db.insert('payments', {
      'id': 'P3',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'reversed',
      'payment_date': '2026-08-07',
    });

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(1100.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('financial columns are derived from loan terms', () async {
    final db = await openDb();
    addTearDown(db.close);
    // 2000 principal @10% interest + 50 charge → expected 2250.
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada',
        amount: 2000, interestRate: 10, charge: 50, installmentAmount: 562.5);

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.amountDisbursed, closeTo(2000.0, 0.001));
        expect(row.interestAmount, closeTo(200.0, 0.001));
        expect(row.expectedAmount, closeTo(2250.0, 0.001));
        // 2250 across 4 weekly installments → 562.50 per week.
        expect(row.weeklyInstallment, closeTo(562.5, 0.001));
        expect(row.outstandingBalance, closeTo(2000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('paymentDay is the weekday of start_date (the weekly anchor)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada',
        startDate: DateTime(2026, 8, 5)); // Wednesday
    await seedWeeklyLoan(db, 'L2', 'C2', 'Beta',
        startDate: DateTime(2026, 8, 7)); // Friday

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        final ada = rows.firstWhere((r) => r.loanId == 'L1');
        final beta = rows.firstWhere((r) => r.loanId == 'L2');
        expect(ada.paymentDay, 'Wednesday');
        expect(beta.paymentDay, 'Friday');
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('installmentDue is the next unpaid installment and remaining is derived',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada');

    // One 550 payment applied → first installment becomes paid.
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-08-06',
    });
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': 550},
      where: "loan_id = 'L1' AND installment_number = 1",
    );

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.installmentDue, closeTo(550.0, 0.001));
        expect(row.amountPaid, closeTo(550.0, 0.001));
        expect(row.remainingBalance, closeTo(1650.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('rows sort alphabetically by customer name', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Zulu');
    await seedWeeklyLoan(db, 'L2', 'C2', 'Alpha');

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows.map((r) => r.customerName).toList(), ['Alpha', 'Zulu']);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('paid installment on the selected date still shows as paid (weekly does not disappear)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada'); // installment 1 due 2026-08-05

    // Pay the full installment 1 (550).
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-08-05',
    });
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': 550},
      where: "loan_id = 'L1' AND installment_number = 1",
    );

    final result =
        await repo(db).getWeeklyCollectionByDate(DateTime(2026, 8, 5));
    result.when(
      success: (rows) {
        // The loan must NOT disappear after paying — it shows as paid.
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentStatus, 'paid');
        expect(row.isCurrentInstallmentPaid, isTrue);
        expect(row.currentInstallmentPaidAmount, closeTo(550.0, 0.001));
        expect(row.collectedThisPeriod, closeTo(550.0, 0.001));
        expect(row.installmentDue, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('unpaid next installment shows pending on its own due date', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada'); // installment 2 due 2026-08-12

    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-08-05',
    });
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': 550},
      where: "loan_id = 'L1' AND installment_number = 1",
    );

    final result =
        await repo(db).getWeeklyCollectionByDate(DateTime(2026, 8, 12));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 2);
        expect(row.currentInstallmentStatus, 'pending');
        expect(row.installmentDue, closeTo(550.0, 0.001));
        expect(row.collectedThisPeriod, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('date with no scheduled installment returns empty (paid or not)', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada'); // installments on Wednesdays

    // Thursday 2026-08-06 is not an installment date.
    final result =
        await repo(db).getWeeklyCollectionByDate(DateTime(2026, 8, 6));
    result.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('range with a paid installment still lists the loan as paid', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada');

    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-08-05',
    });
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': 550},
      where: "loan_id = 'L1' AND installment_number = 1",
    );

    final result = await repo(db)
        .getWeeklyCollectionByDateRange(DateTime(2026, 8, 3), DateTime(2026, 8, 7));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.currentInstallmentStatus, 'paid');
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('overdueAmount accumulates every unpaid installment due before today',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    // 2000 @10% + no charge → 2200 total, 4 weekly installments of 550 each,
    // all due in January 2026 (well before "today" in the real test clock).
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada',
        startDate: DateTime(2026, 1, 7), // Wednesday
        amount: 2000,
        interestRate: 10);

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.overdueAmount, closeTo(2200.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('overdueAmount counts only unpaid past installments (money rule)',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada',
        startDate: DateTime(2026, 1, 7), amount: 2000, interestRate: 10);

    // Pay installment 1 in full → only installments 2-4 (1650) stay overdue.
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 550,
      'status': 'completed',
      'payment_date': '2026-01-08',
    });
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': 550},
      where: "loan_id = 'L1' AND installment_number = 1",
    );

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.overdueAmount, closeTo(1650.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('overdueAmount flows through the date-range query', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyLoan(db, 'L1', 'C1', 'Ada',
        startDate: DateTime(2026, 1, 7), amount: 2000, interestRate: 10);

    final result = await repo(db)
        .getWeeklyCollectionByDateRange(DateTime(2026, 1, 7), DateTime(2026, 1, 8));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.overdueAmount, closeTo(2200.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('paymentDaySortValue groups by repayment day Monday to Sunday', () async {
    final db = await openDb();
    addTearDown(db.close);
    // 2026-08-05 = Wednesday, 2026-08-07 = Friday, 2026-08-03 = Monday.
    await seedWeeklyLoan(db, 'L1', 'C1', 'Wed Person',
        startDate: DateTime(2026, 8, 5));
    await seedWeeklyLoan(db, 'L2', 'C2', 'Fri Person',
        startDate: DateTime(2026, 8, 7));
    await seedWeeklyLoan(db, 'L3', 'C3', 'Mon Person',
        startDate: DateTime(2026, 8, 3));

    final result = await repo(db).getWeeklyCollectionByDateRange(DateTime(2020, 1, 1), DateTime(2100, 1, 1));
    result.when(
      success: (rows) {
        final sorted = [...rows]
          ..sort((a, b) {
            final byDay = a.paymentDaySortValue.compareTo(b.paymentDaySortValue);
            if (byDay != 0) return byDay;
            return a.customerName.toLowerCase().compareTo(b.customerName.toLowerCase());
          });
        expect(sorted.map((r) => r.paymentDay).toList(),
            ['Monday', 'Wednesday', 'Friday']);
        expect(sorted.first.customerName, 'Mon Person');
        expect(sorted.last.customerName, 'Fri Person');
        // Weekday order: Monday(1) < Wednesday(3) < Friday(5).
        expect(sorted[0].paymentDaySortValue, lessThan(sorted[1].paymentDaySortValue));
        expect(sorted[1].paymentDaySortValue, lessThan(sorted[2].paymentDaySortValue));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}
