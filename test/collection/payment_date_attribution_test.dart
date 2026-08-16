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
        id TEXT PRIMARY KEY, full_name TEXT NOT NULL, phone TEXT,
        group_id TEXT, guarantor_1_name TEXT, guarantor_1_phone TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, loan_type TEXT NOT NULL,
        amount REAL NOT NULL, interest_rate REAL NOT NULL,
        insurance_fee REAL DEFAULT 0.0, commission REAL DEFAULT 0.0,
        processing_fee REAL DEFAULT 0.0, admin_fee REAL DEFAULT 0.0,
        other_charges REAL DEFAULT 0.0, loan_date TEXT NOT NULL,
        start_date TEXT NOT NULL, duration_days INTEGER,
        duration_weeks INTEGER, repayment_frequency TEXT,
        daily_payment REAL, weekly_payment REAL, total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL, expected_completion_date TEXT NOT NULL,
        custom_collection_amount REAL, collector TEXT, notes TEXT,
        status TEXT NOT NULL, updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE repayment_schedule (
        id TEXT PRIMARY KEY, loan_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL, due_date TEXT NOT NULL,
        amount REAL NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
        paid_amount REAL NOT NULL DEFAULT 0.0
      )
    ''');
    await db.execute('''
      CREATE TABLE customer_groups (id TEXT PRIMARY KEY, name TEXT NOT NULL)
    ''');
    await db.execute('''
      CREATE TABLE holidays (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, date TEXT NOT NULL,
        is_recurring INTEGER NOT NULL, is_enabled INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY, loan_id TEXT NOT NULL, customer_id TEXT NOT NULL,
        amount REAL NOT NULL, status TEXT NOT NULL, payment_date TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY, customer_id TEXT NOT NULL, amount REAL NOT NULL,
        type TEXT NOT NULL, reference_loan_payment_id TEXT, created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY, customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0, created_at TEXT NOT NULL, updated_at TEXT
      )
    ''');
    return db;
  }

  Future<void> seedWeekly(
    Database db,
    String loanId,
    String customerId,
    String name,
    DateTime startDate,
  ) async {
    await db.insert('customers', {
      'id': customerId, 'full_name': name, 'phone': '0801',
      'guarantor_1_name': 'G', 'guarantor_1_phone': '0802',
    });
    const amount = 2000.0;
    const totalRepayment = 2200.0;
    final loan = Loan(
      id: loanId, customerId: customerId, loanType: LoanType.weekly,
      status: LoanStatus.active, amount: amount, interestRate: 10,
      duration: 4, loanDate: DateTime(2026, 7, 20), repaymentStartDate: startDate,
      totalRepayment: totalRepayment, outstandingBalance: 2200,
      installmentAmount: 550, expectedCompletionDate: DateTime(2026, 9, 1),
    );
    final amounts = CurrencyUtils.splitEvenly(totalRepayment, 4);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId, loanType: LoanType.weekly, startDate: startDate,
      amounts: amounts, holidays: const [],
    );
    await db.insert('loans', loan.toMap());
    for (final inst in schedule) {
      await db.insert('repayment_schedule', inst.toMap());
    }
  }

  Future<void> seedDaily(
    Database db,
    String loanId,
    String customerId,
    String name,
    DateTime startDate,
  ) async {
    await db.insert('customers', {
      'id': customerId, 'full_name': name, 'phone': '0801',
    });
    final loan = Loan(
      id: loanId, customerId: customerId, loanType: LoanType.daily,
      status: LoanStatus.active, amount: 5000, interestRate: 0,
      duration: 5, loanDate: DateTime(2026, 8, 1), repaymentStartDate: startDate,
      totalRepayment: 5000, outstandingBalance: 5000,
      installmentAmount: 1000, expectedCompletionDate: DateTime(2026, 8, 7),
    );
    final amounts = CurrencyUtils.splitEvenly(5000, 5);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId, loanType: LoanType.daily, startDate: startDate,
      amounts: amounts, holidays: const [],
    );
    await db.insert('loans', loan.toMap());
    for (final inst in schedule) {
      await db.insert('repayment_schedule', inst.toMap());
    }
  }

  Future<void> insertPayment(Database db, String loanId, String customerId,
      String id, double amount, String date,
      {String status = 'completed'}) async {
    await db.insert('payments', {
      'id': id, 'loan_id': loanId, 'customer_id': customerId,
      'amount': amount, 'status': status, 'payment_date': date,
    });
  }

  /// Marks an installment paid, the way PaymentRepository recalculates the
  /// schedule after a completed payment.
  Future<void> markInstallmentPaid(Database db, String loanId,
      int installmentNumber, double amount) async {
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': amount},
      where: 'loan_id = ? AND installment_number = ?',
      whereArgs: [loanId, installmentNumber],
    );
  }

  CollectionRepository repo(Database db) =>
      CollectionRepository(_FakeDatabaseService(db));

  test(
      'weekly: a late payment shows as collected in the WEEK IT PAYS FOR, not '
      'the week the money arrived (installment-week attribution)', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Weekly installments: Mon 07-27, Mon 08-03, Mon 08-10, Mon 08-17 (550 each).
    await seedWeekly(db, 'L1', 'C1', 'Ada', DateTime(2026, 7, 27));

    // Ada misses W1 (07-27); on Mon 08-10 she pays 550, which clears the OLDEST
    // unpaid installment (07-27). Her current unpaid installment is W3 (08-10).
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-10');
    await markInstallmentPaid(db, 'L1', 1, 550);
    await db.rawUpdate(
      "UPDATE loans SET outstanding_balance = 1650 WHERE id = 'L1'",
    );

    // The week the money PAYS FOR (W1, 07-27): shows as paid with the applied
    // amount — NOT 0 as under the old money-date rule.
    final paidWeek = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 7, 27), DateTime(2026, 7, 31));
    paidWeek.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 1);
        expect(row.currentInstallmentStatus, 'paid');
        expect(row.collectedThisPeriod, closeTo(550.0, 0.001));
        expect(row.isPaidForPeriod, isTrue);
        expect(row.installmentDue, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );

    // The week the money ARRIVED (08-10): the row is tied to its in-range
    // installment (W3), which is still unpaid — nothing collected there.
    final arrivalWeek = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 10), DateTime(2026, 8, 14));
    arrivalWeek.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 3);
        expect(row.currentInstallmentDueDate, '2026-08-10');
        expect(row.currentInstallmentStatus, 'pending');
        expect(row.collectedThisPeriod, closeTo(0.0, 0.001));
        expect(row.isPaidForPeriod, isFalse);
        expect(row.installmentDue, closeTo(550.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test('weekly: the cleared week shows the money — the row is the week paid for',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeekly(db, 'L1', 'C1', 'Ada', DateTime(2026, 7, 27));

    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-10');
    await markInstallmentPaid(db, 'L1', 1, 550);
    await db.rawUpdate(
      "UPDATE loans SET outstanding_balance = 1650 WHERE id = 'L1'",
    );

    // Viewing the week whose installment the payment cleared (07-27): the loan
    // shows as PAID, because that is the week the 550 pays for.
    final result = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 7, 27), DateTime(2026, 7, 31));
    result.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.collectedThisPeriod, closeTo(550.0, 0.001));
        expect(row.currentInstallmentNumber, 1);
        expect(row.currentInstallmentStatus, 'paid');
        expect(row.isPaidForPeriod, isTrue);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'weekly: a payment received on a non-installment day lights up the week '
      'it pays for, and the non-installment day itself is empty', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeekly(db, 'L1', 'C1', 'Ada', DateTime(2026, 7, 27));

    // Ada pays on Wed 08-12 — a day with no scheduled weekly installment
    // (her payment days are Mondays). It clears the oldest unpaid installment.
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-12');
    await markInstallmentPaid(db, 'L1', 1, 550);

    // The non-installment day itself now shows nothing (visibility is driven
    // by installments only, not by money received).
    final nonInstallmentDay = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 12), DateTime(2026, 8, 12));
    nonInstallmentDay.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );

    // The week the money pays for (W1): paid with the applied amount.
    final paidWeek = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 7, 27), DateTime(2026, 7, 31));
    paidWeek.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 1);
        expect(row.currentInstallmentStatus, 'paid');
        expect(row.collectedThisPeriod, closeTo(550.0, 0.001));
        expect(row.isPaidForPeriod, isTrue);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'weekly: the owner example — 550 due Wednesday, paid Saturday, shows on '
      'Wednesday as paid and never on Saturday', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Weekly installments anchored to Wednesday 08-05.
    await seedWeekly(db, 'L1', 'C1', 'Ada', DateTime(2026, 8, 5));

    // Ada pays the 550 for Wednesday 08-05 on Saturday 08-08.
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-08');
    await markInstallmentPaid(db, 'L1', 1, 550);

    // Saturday itself: no weekly installment → empty.
    final saturday = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 8), DateTime(2026, 8, 8));
    saturday.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );

    // Wednesday 08-05 (the week it pays for): paid with the 550.
    final wednesday = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 5), DateTime(2026, 8, 5));
    wednesday.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentDueDate, '2026-08-05');
        expect(row.currentInstallmentStatus, 'paid');
        expect(row.collectedThisPeriod, closeTo(550.0, 0.001));
        expect(row.isPaidForPeriod, isTrue);
      },
      failure: (f) => fail('query failed: $f'),
    );

    // Next Wednesday 08-12: the loan is still listed but that week is unpaid.
    final nextWeek = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 12), DateTime(2026, 8, 12));
    nextWeek.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 2);
        expect(row.currentInstallmentStatus, 'pending');
        expect(row.collectedThisPeriod, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'daily: a weekend payment counts on the PRECEDING Friday; Saturday and '
      'Sunday themselves are always empty', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Daily installments Mon 08-03 .. Fri 08-07 (1000 each).
    await seedDaily(db, 'L1', 'C1', 'Ada', DateTime(2026, 8, 3));

    // Ada pays her Friday installment (1000) on Saturday 08-08.
    await insertPayment(db, 'L1', 'C1', 'P1', 1000, '2026-08-08');
    await markInstallmentPaid(db, 'L1', 5, 1000);

    // Saturday and Sunday views are empty (no daily collection on weekends).
    final saturday = await repo(db).getDailyCollection(DateTime(2026, 8, 8));
    saturday.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );
    final sunday = await repo(db).getDailyCollection(DateTime(2026, 8, 9));
    sunday.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );

    // The preceding Friday: the loan shows with the weekend money collected.
    final friday = await repo(db).getDailyCollection(DateTime(2026, 8, 7));
    friday.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(1000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );

    // A range ending on Friday absorbs the weekend into its totals.
    final fridayEndRange = await repo(db).getCollectionsByDateRange(
        DateTime(2026, 8, 3), DateTime(2026, 8, 7), loanType: 'daily');
    fridayEndRange.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(1000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );

    // A range that starts on the weekend WITHOUT its Friday stays empty: the
    // Saturday money belongs to the Friday before the range.
    final weekendOnly = await repo(db).getCollectionsByDateRange(
        DateTime(2026, 8, 8), DateTime(2026, 8, 9), loanType: 'daily');
    weekendOnly.when(
      success: (rows) => expect(rows, isEmpty),
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'daily: money received on the payment day clears arrears but still shows '
      'as collected that day, and the week range aggregates it', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Daily installments Mon 08-03 .. Fri 08-07 (1000 each).
    await seedDaily(db, 'L1', 'C1', 'Ada', DateTime(2026, 8, 3));

    // Ada misses Mon + Tue; on Wed 08-05 she pays 2000, which clears the two
    // oldest unpaid installments (Mon + Tue). Her Wed installment stays unpaid.
    await insertPayment(db, 'L1', 'C1', 'P1', 2000, '2026-08-05');
    await markInstallmentPaid(db, 'L1', 1, 1000);
    await markInstallmentPaid(db, 'L1', 2, 1000);
    await db.rawUpdate(
      "UPDATE loans SET outstanding_balance = 3000 WHERE id = 'L1'",
    );

    // The payment day: amountPaid is the money received ON that day.
    final single = await repo(db).getDailyCollection(DateTime(2026, 8, 5));
    single.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.amountPaid, closeTo(2000.0, 0.001));
        expect(row.amountDue, closeTo(1000.0, 0.001));
        expect(row.scheduleStatus, 'pending');
      },
      failure: (f) => fail('query failed: $f'),
    );

    // The whole week in range mode: 2000 collected, 3000 still due (Wed+Thu+Fri).
    final range = await repo(db).getCollectionsByDateRange(
        DateTime(2026, 8, 3), DateTime(2026, 8, 7), loanType: 'daily');
    range.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(2000.0, 0.001));
        expect(rows.first.amountDue, closeTo(3000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'weekly: after a partial payment the loan keeps showing on later weeks '
      'until it is completed', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeekly(db, 'L1', 'C1', 'Ada', DateTime(2026, 7, 27));

    // Ada misses W1 (07-27); on 08-10 she pays 550, which clears only the
    // oldest missed installment. W2, W3, W4 are still owing.
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-10');
    await markInstallmentPaid(db, 'L1', 1, 550);
    await db.rawUpdate(
      "UPDATE loans SET outstanding_balance = 1650 WHERE id = 'L1'",
    );

    // The NEXT week (W4 due 08-17): the loan must still be listed — not yet
    // completed — but with no money collected in that week.
    final nextWeek = await repo(db).getWeeklyCollectionByDateRange(
        DateTime(2026, 8, 17), DateTime(2026, 8, 21));
    nextWeek.when(
      success: (rows) {
        expect(rows, hasLength(1));
        final row = rows.first;
        expect(row.currentInstallmentNumber, 4);
        expect(row.collectedThisPeriod, closeTo(0.0, 0.001));
        expect(row.isPaidForPeriod, isFalse);
      },
      failure: (f) => fail('query failed: $f'),
    );
  });

  test(
      'daily: after clearing arrears on one day the loan keeps showing on the '
      'following days until it is completed', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedDaily(db, 'L1', 'C1', 'Ada', DateTime(2026, 8, 3));

    // Ada misses Mon + Tue; on Wed 08-05 she pays 2000 clearing both. Her
    // Wed, Thu, Fri installments are still owing, so the loan is not completed.
    await insertPayment(db, 'L1', 'C1', 'P1', 2000, '2026-08-05');
    await markInstallmentPaid(db, 'L1', 1, 1000);
    await markInstallmentPaid(db, 'L1', 2, 1000);
    await db.rawUpdate(
      "UPDATE loans SET outstanding_balance = 3000 WHERE id = 'L1'",
    );

    // The day AFTER the payment (Thu 08-06): still listed, no money collected
    // that day, so it is not shown as paid — but it must not disappear.
    final nextDay = await repo(db).getDailyCollection(DateTime(2026, 8, 6));
    nextDay.when(
      success: (rows) {
        expect(rows, hasLength(1));
        expect(rows.first.amountPaid, closeTo(0.0, 0.001));
        expect(rows.first.amountDue, closeTo(1000.0, 0.001));
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}
