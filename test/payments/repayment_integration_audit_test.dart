import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/database/migrations.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/loans/data/loan_repository.dart';
import 'package:loantrack/features/loans/data/loan_schedule_service.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';
import 'package:loantrack/features/payments/data/payment_repository.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';
import 'package:loantrack/features/reports/data/report_repository.dart';
import 'package:loantrack/features/savings/data/savings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show
        OpenDatabaseOptions,
        databaseFactoryFfi,
        inMemoryDatabasePath,
        sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

/// Final pre-release repayment-logic audit.
///
/// Runs against a REAL SQLite engine with the full production schema
/// (fresh-install DDL from `DatabaseService._onCreate` + `createSyncSchema`),
/// so the repayment write path and every downstream read path
/// (schedule, savings, history, collection screens, reports, dashboard,
/// cloud-change-tracking) are exercised together — not as isolated unit
/// functions.
///
/// The core invariant asserted after every repayment:
///   outstanding = total_repayment − Σ(completed payment.amount − overpayment surplus)
/// and that the surplus is NEVER double-counted as collected or loan-applied.

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());
  final Database _db;
  @override
  Future<Database> get database async => _db;
}

/// Replicates `DatabaseService._onCreate` + `_createIndexes` +
/// `createSyncSchema` for a fresh install, so the audit uses the exact
/// production schema (column names must match the schema crosscheck guard).
Future<Database> openFullSchemaDb() async {
  // 24 = the current `_databaseVersion` in database_service.dart. Keep this in
  // sync with a fresh-install schema whenever a new migration lands.
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 24));
  final creates = <String>[
    '''
    CREATE TABLE business_profile (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      logo_path TEXT,
      address TEXT,
      phone TEXT,
      email TEXT,
      reg_no TEXT,
      owner_name TEXT,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE customer_groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      passport_path TEXT,
      full_name TEXT NOT NULL,
      gender TEXT,
      dob TEXT,
      phone TEXT NOT NULL,
      alt_phone TEXT,
      email TEXT,
      residential_address TEXT,
      business_address TEXT,
      occupation TEXT,
      employer TEXT,
      marital_status TEXT,
      nationality TEXT,
      state TEXT,
      lga TEXT,
      next_of_kin TEXT,
      next_of_kin_relation TEXT,
      next_of_kin_phone TEXT,
      guarantor_1_name TEXT,
      guarantor_1_phone TEXT,
      guarantor_1_address TEXT,
      guarantor_2_name TEXT,
      guarantor_2_phone TEXT,
      guarantor_2_address TEXT,
      guarantor_passport_path TEXT,
      nin TEXT,
      bvn TEXT,
      id_type TEXT,
      id_number TEXT,
      signature_path TEXT,
      date_registered TEXT NOT NULL,
      notes TEXT,
      status TEXT NOT NULL,
      credit_score REAL DEFAULT 0.0,
      group_id TEXT REFERENCES customer_groups(id) ON DELETE SET NULL,
      updated_at TEXT
    )
    ''',
    '''
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
      updated_at TEXT,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE payments (
      id TEXT PRIMARY KEY,
      loan_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      amount REAL NOT NULL,
      payment_date TEXT NOT NULL,
      payment_method TEXT NOT NULL,
      reference_no TEXT,
      receipt_no TEXT UNIQUE NOT NULL,
      collector TEXT NOT NULL,
      remarks TEXT,
      type TEXT DEFAULT 'partial',
      status TEXT NOT NULL DEFAULT 'completed',
      prior_loan_status TEXT,
      client_request_id TEXT,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE repayment_schedule (
      id TEXT PRIMARY KEY,
      loan_id TEXT NOT NULL,
      installment_number INTEGER NOT NULL,
      due_date TEXT NOT NULL,
      amount REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      paid_amount REAL NOT NULL DEFAULT 0.0,
      updated_at TEXT,
      FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE documents (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      loan_id TEXT,
      doc_type TEXT NOT NULL,
      file_path TEXT NOT NULL,
      original_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      uploaded_at TEXT NOT NULL,
      updated_at TEXT,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
      FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE holidays (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      date TEXT NOT NULL,
      is_recurring INTEGER NOT NULL,
      is_enabled INTEGER NOT NULL,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE audit_logs (
      id TEXT PRIMARY KEY,
      user TEXT NOT NULL,
      action TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      details TEXT NOT NULL,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT
    )
    ''',
    '''
    CREATE TABLE savings_accounts (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL UNIQUE,
      balance REAL NOT NULL DEFAULT 0.0,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE TABLE savings_transactions (
      id TEXT PRIMARY KEY,
      savings_account_id TEXT NOT NULL,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      reference_loan_payment_id TEXT,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT,
      FOREIGN KEY (savings_account_id) REFERENCES savings_accounts(id) ON DELETE CASCADE
    )
    ''',
  ];
  for (final create in creates) {
    await db.execute(create);
  }
  for (final index in const [
    'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(full_name)',
    'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_unique ON customers(phone) WHERE status != 'archived'",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_nin_unique ON customers(nin) WHERE status != 'archived'",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_bvn_unique ON customers(bvn) WHERE status != 'archived'",
    'CREATE INDEX IF NOT EXISTS idx_customers_group ON customers(group_id)',
    'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)',
    'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan ON repayment_schedule(loan_id)',
    'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)',
    'CREATE INDEX IF NOT EXISTS idx_customer_groups_name ON customer_groups(name)',
    'CREATE INDEX IF NOT EXISTS idx_savings_accounts_customer ON savings_accounts(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_savings_transactions_account ON savings_transactions(savings_account_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_loan_date ON payments(loan_id, payment_date)',
    'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan_date ON repayment_schedule(loan_id, due_date)',
    'CREATE INDEX IF NOT EXISTS idx_loans_type_status ON loans(loan_type, status)',
    'CREATE INDEX IF NOT EXISTS idx_loans_type_date ON loans(loan_type, loan_date)',
    'CREATE INDEX IF NOT EXISTS idx_savings_txns_ref_payment ON savings_transactions(reference_loan_payment_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)',
    'CREATE INDEX IF NOT EXISTS idx_savings_txns_created ON savings_transactions(created_at)',
    'CREATE INDEX IF NOT EXISTS idx_holidays_date ON holidays(date)',
    'CREATE INDEX IF NOT EXISTS idx_documents_loan ON documents(loan_id)',
  ]) {
    await db.execute(index);
  }
  await DatabaseMigrations.createSyncSchema(db);
  return db;
}

class _Harness {
  _Harness(this.db) {
    service = _FakeDatabaseService(db);
    final notifier = LoanScheduleVersionNotifier();
    scheduleService = LoanScheduleService(service, notifier);
    loanRepo = LoanRepository(service, scheduleService: scheduleService);
    paymentRepo = PaymentRepository(service, scheduleService: scheduleService);
    collectionRepo = CollectionRepository(service);
    reportRepo = ReportRepository(service);
    savingsRepo = SavingsRepository(service);
  }

  final Database db;
  late final DatabaseService service;
  late final LoanScheduleService scheduleService;
  late final LoanRepository loanRepo;
  late final PaymentRepository paymentRepo;
  late final CollectionRepository collectionRepo;
  late final ReportRepository reportRepo;
  late final SavingsRepository savingsRepo;

  Future<void> seedCustomer(String id, String name) async {
    await db.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': '080$id',
      'date_registered': '2026-08-01',
      'status': 'active',
    });
  }

  /// Creates a loan through the real [LoanRepository] so the repo validation
  /// and the derived-schedule rebuild run exactly as in production.
  Future<String> seedLoan({
    required String loanId,
    required String customerId,
    required LoanType loanType,
    required double amount,
    required double interestRate,
    required int duration,
    DateTime? startDate,
    double? customCollectionAmount,
  }) async {
    final start = startDate ?? DateTime.now();
    final total = CurrencyUtils.roundToCents(
        amount + amount * interestRate / 100);
    final installment = CurrencyUtils.roundToCents(total / duration);
    final loan = Loan(
      id: loanId,
      customerId: customerId,
      loanType: loanType,
      amount: amount,
      interestRate: interestRate,
      duration: duration,
      loanDate: start,
      repaymentStartDate: start,
      totalRepayment: total,
      outstandingBalance: total,
      installmentAmount: installment,
      expectedCompletionDate: start.add(Duration(days: duration)),
      customCollectionAmount: customCollectionAmount,
    );
    final amounts = CurrencyUtils.splitEvenly(total, duration);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId,
      loanType: loanType,
      startDate: start,
      amounts: amounts,
      holidays: const [],
    );
    final result = await loanRepo.saveLoanAndSchedule(loan, schedule);
    expect(result.isSuccess, isTrue,
        reason: 'seedLoan failed: ${result.failureOrNull}');
    return loanId;
  }

  Future<Map<String, Object?>> loanRow(String loanId) async {
    final rows = await db.query('loans',
        where: 'id = ?', whereArgs: [loanId], limit: 1);
    return rows.single;
  }

  Future<List<Map<String, Object?>>> scheduleRows(String loanId) async {
    return db.query('repayment_schedule',
        where: 'loan_id = ?', whereArgs: [loanId], orderBy: 'installment_number ASC');
  }

  Future<double> savingsBalance(String customerId) async {
    final rows = await db.query('savings_accounts',
        columns: ['balance'],
        where: 'customer_id = ?', whereArgs: [customerId], limit: 1);
    if (rows.isEmpty) return 0.0;
    return (rows.single['balance'] as num?)?.toDouble() ?? 0.0;
  }
}

final _syncStampPattern =
    RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');

void main() {
  sqfliteFfiInit();

  group('repayment write path (real SQLite + production schema)', () {
    test('FULL repayment: settles the loan, completes every installment, no savings side effect',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 5000, interestRate: 0, duration: 5);

      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 5000,
        method: PaymentMethod.cash, collector: 'Admin',
      );

      expect(payment.type, PaymentType.full);
      expect(payment.status, PaymentStatus.completed);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 0.0);
      expect(loan['status'], 'completed');

      final schedule = await h.scheduleRows('L1');
      expect(schedule, hasLength(5));
      for (final row in schedule) {
        expect(row['status'], 'paid');
        expect((row['paid_amount'] as num).toDouble(),
            (row['amount'] as num).toDouble());
      }
      expect(await h.savingsBalance('C1'), 0.0,
          reason: 'exact full payment must not create savings surplus');
      final savingsTxns = await db
          .query('savings_transactions');
      expect(savingsTxns, isEmpty);
    });

    test('PARTIAL repayment: outstanding = expected − paid, status stays active',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 3000,
        method: PaymentMethod.cash, collector: 'Admin',
      );
      expect(payment.type, PaymentType.partial);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 7000);
      expect(loan['status'], 'active');

      final schedule = await h.scheduleRows('L1');
      expect(schedule[0]['status'], 'paid',
          reason: 'oldest-first allocation: installment 1 is fully covered');
      expect((schedule[0]['paid_amount'] as num).toDouble(), 2000);
      expect(schedule[1]['status'], 'partial',
          reason: 'installment 2 holds the remaining 1000 of the 3000');
      expect((schedule[1]['paid_amount'] as num).toDouble(), 1000);
      expect(schedule.last['status'], 'pending');
      expect((schedule.last['paid_amount'] as num).toDouble(), 0);
    });

    test('MULTIPLE repayments: outstanding decreases each time and reaches 0',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      for (final (amount, expectedOutstanding) in [
        (3000.0, 7000.0),
        (3000.0, 4000.0),
        (4000.0, 0.0),
      ]) {
        await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: amount,
          method: PaymentMethod.cash, collector: 'Admin',
        );
        final loan = await h.loanRow('L1');
        expect((loan['outstanding_balance'] as num).toDouble(),
            expectedOutstanding,
            reason: 'after paying $amount');
        if (expectedOutstanding == 0) {
          expect(loan['status'], 'completed');
        } else {
          expect(loan['status'], 'active');
        }
      }

      final payments = await db.query('payments');
      expect(payments, hasLength(3),
          reason: 'exactly 3 payment rows — no double-count');
      final totalApplied = payments.fold<double>(0.0, (sum, p) =>
          sum + ((p['amount'] as num).toDouble()));
      expect(totalApplied, 10000);
      // No overpayments → no savings transactions at all.
      expect(await db.query('savings_transactions'), isEmpty);
    });

    test('OVERPAYMENT with installment context: excess credited to savings, loan capped at installment',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 10,
          customCollectionAmount: 1000);

      // Exactly what `collection_screen.dart` passes:
      // installmentDue = installment amount − already-paid = 1000.
      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 1500,
        method: PaymentMethod.cash, collector: 'Admin',
        installmentDue: 1000,
      );

      expect(payment.type, PaymentType.overpayment);
      final loan = await h.loanRow('L1');
      // Only the installment (1000) is applied; the extra 500 goes to savings.
      expect((loan['outstanding_balance'] as num).toDouble(), 9000);
      expect(loan['status'], 'active');

      expect(await h.savingsBalance('C1'), 500);
      final stx = await db.query('savings_transactions');
      expect(stx, hasLength(1));
      expect(stx.single['type'], 'overpayment');
      expect((stx.single['amount'] as num).toDouble(), 500);
      expect(stx.single['reference_loan_payment_id'], payment.id,
          reason: 'surplus must be linked to the payment row');

      // Collected must be 1000, NEVER the gross 1500 (money rule).
      final schedule = await h.scheduleRows('L1');
      expect((schedule.first['paid_amount'] as num).toDouble(), 1000);
    });

    test('OVERPAYMENT without installment context: pay-in-full caps at outstanding, surplus to savings',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 12000,
        method: PaymentMethod.cash, collector: 'Admin',
      );

      expect(payment.type, PaymentType.overpayment);
      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 0.0);
      expect(loan['status'], 'completed');
      expect(await h.savingsBalance('C1'), 2000);

      final stx = await db.query('savings_transactions');
      expect(stx.single['type'], 'overpayment');
      expect((stx.single['amount'] as num).toDouble(), 2000);
    });

    test('ZERO repayment is rejected (never writes a row)', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      await expectLater(
        h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 0,
          method: PaymentMethod.cash, collector: 'Admin',
        ),
        throwsException,
      );
      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 10000);
      expect(await db.query('payments'), isEmpty);
    });

    test('INVALID repayments (negative, NaN, Infinity) are rejected', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      for (final bad in [-500.0, double.nan, double.infinity]) {
        await expectLater(
          h.paymentRepo.createPayment(
            loanId: 'L1', customerId: 'C1', amount: bad,
            method: PaymentMethod.cash, collector: 'Admin',
          ),
          throwsException,
          reason: '$bad must be rejected',
        );
      }
      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 10000);
      expect(await db.query('payments'), isEmpty);
    });

    test('REPAYMENT AFTER PREVIOUS PARTIAL: completes the loan with the remainder',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 3000,
        method: PaymentMethod.cash, collector: 'Admin',
      );
      final loanAfterPartial = await h.loanRow('L1');
      expect((loanAfterPartial['outstanding_balance'] as num).toDouble(), 7000);

      final finalPayment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 7000,
        method: PaymentMethod.cash, collector: 'Admin',
      );
      expect(finalPayment.type, PaymentType.full);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 0.0);
      expect(loan['status'], 'completed');
      final schedule = await h.scheduleRows('L1');
      for (final row in schedule) {
        expect(row['status'], 'paid');
      }
    });

    test('REPAYMENT THAT COMPLETES A LOAN: status completes, no surplus', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 2500, interestRate: 0, duration: 1);

      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 2500,
        method: PaymentMethod.cash, collector: 'Admin',
      );
      expect(payment.type, PaymentType.full);
      final loan = await h.loanRow('L1');
      expect(loan['status'], 'completed');
      expect((loan['outstanding_balance'] as num).toDouble(), 0.0);
      expect(await h.savingsBalance('C1'), 0.0);
    });

    test('PAYMENT ON A CLOSED LOAN is rejected at the repository boundary', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 1000, interestRate: 0, duration: 1);
      await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 1000,
        method: PaymentMethod.cash, collector: 'Admin',
      );

      await expectLater(
        h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 500,
          method: PaymentMethod.cash, collector: 'Admin',
        ),
        throwsException,
        reason: 'a completed loan must not accept more money',
      );

      // The attempted payment must not have been recorded nor credited savings.
      final payments = await db.query('payments');
      expect(payments, hasLength(1));
      expect(await db.query('savings_transactions'), isEmpty);
    });

    test('IDEMPOTENCY: retrying the same client request id records ONE payment (double-count guard)',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      final first = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 3000,
        method: PaymentMethod.cash, collector: 'Admin',
        clientRequestId: 'req-double-tap',
      );
      final second = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 3000,
        method: PaymentMethod.cash, collector: 'Admin',
        clientRequestId: 'req-double-tap',
      );

      expect(second.id, first.id, reason: 'same logical payment');
      final payments = await db.query('payments');
      expect(payments, hasLength(1));
      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 7000,
          reason: 'applied exactly once');
    });
  });

  group('repayment downstream effects (reports, collections, dashboard, history, cloud)', () {
    test('history, outstanding, schedule, status, savings all reflect a partial repayment',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      final payment = await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 3000,
        method: PaymentMethod.transfer, collector: 'Op',
        referenceNumber: 'REF-001',
        remarks: 'first tranche',
      );

      // ── Loan history records the transaction ─────────────────────────
      final history = await h.paymentRepo.getPaymentsForLoan('L1');
      expect(history, hasLength(1));
      expect(history.single.id, payment.id);
      expect(history.single.amount, 3000);
      expect(history.single.method, PaymentMethod.transfer);
      expect(history.single.type, PaymentType.partial);
      expect(history.single.status, PaymentStatus.completed);
      expect(history.single.collector, 'Op');
      expect(history.single.referenceNumber, 'REF-001');
      expect(history.single.priorLoanStatus, 'active');
      expect(history.single.receiptNumber, isNotEmpty);
      expect(history.single.receiptNumber, startsWith('REC-'));

      // ── Outstanding + status ─────────────────────────────────────────
      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 7000);
      expect(loan['status'], 'active');
    });

    test('collected amount updates in reports/collections and excludes the savings surplus (money rule)',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 10,
          customCollectionAmount: 1000);

      await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 1500,
        method: PaymentMethod.cash, collector: 'Op',
        installmentDue: 1000,
      );

      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);
      final endOfToday =
          DateTime(today.year, today.month, today.day, 23, 59, 59);

      // ── Report summary (dashboard "Total Collected") ─────────────────
      final summary = (await h.reportRepo
              .getReportSummary(startOfToday, endOfToday))
          .dataOrNull;
      expect(summary, isNotNull);
      expect(summary!.totalCollected, closeTo(1000, 0.001),
          reason: 'gross 1500 must NOT be collected — 500 went to savings');
      expect(summary.dailyLoans.savingsFromOverpayments, closeTo(500, 0.001));
      expect(summary.dailyLoans.outstandingBalance, closeTo(9000, 0.001));

      // ── Collection screen (range view) ───────────────────────────────
      final range = (await h.collectionRepo
              .getCollectionsByDateRange(startOfToday, endOfToday))
          .dataOrNull;
      expect(range, isNotNull);
      expect(range!.single.amountPaid, closeTo(1000, 0.001),
          reason: 'collection screen must apply the money rule too');
      expect(range.single.outstandingBalance, closeTo(9000, 0.001));

      // ── Collection screen (single-day view) ──────────────────────────
      final singleDay = (await h.collectionRepo
              .getDailyCollection(startOfToday))
          .dataOrNull;
      expect(singleDay, isNotNull);
      expect(singleDay!.single.amountPaid, closeTo(1000, 0.001));

      // ── Report dashboard ─────────────────────────────────────────────
      final dashboard = (await h.reportRepo
              .getReportDashboard(startOfToday, endOfToday))
          .dataOrNull;
      expect(dashboard, isNotNull);
      expect(dashboard!.summary.totalCollected, closeTo(1000, 0.001));
      expect(dashboard.today.collectedAmount, closeTo(1000, 0.001));
      expect(dashboard.savings.totalBalance, closeTo(500, 0.001));
      expect(dashboard.savings.inflow, closeTo(500, 0.001),
          reason: 'overpayment counts as savings inflow');
      expect(dashboard.totalOutstandingBalance, closeTo(9000, 0.001));
    });

    test('multiple partial repayments sum correctly in every aggregate (no missed payments)',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 2500,
          method: PaymentMethod.cash, collector: 'Op');
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 2500,
          method: PaymentMethod.cash, collector: 'Op');
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 2500,
          method: PaymentMethod.cash, collector: 'Op');

      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 2500);

      final summary = (await h.reportRepo.getReportSummary(start, end))
          .dataOrNull!;
      expect(summary.totalCollected, closeTo(7500, 0.001));

      final range = (await h.collectionRepo
              .getCollectionsByDateRange(start, end))
          .dataOrNull!;
      expect(range.single.amountPaid, closeTo(7500, 0.001));

      final dashboard =
          (await h.reportRepo.getReportDashboard(start, end)).dataOrNull!;
      expect(dashboard.summary.totalCollected, closeTo(7500, 0.001));
      expect(dashboard.totalOutstandingBalance, closeTo(2500, 0.001));
      expect(dashboard.today.paymentCount, 3);
    });

    test('weekly collection screen reflects the payment and the savings balance',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.weekly,
          amount: 2000, interestRate: 10, duration: 4);

      await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 550,
        method: PaymentMethod.cash, collector: 'Op',
        installmentDue: 550,
      );

      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = DateTime(today.year, today.month, today.day, 23, 59, 59);

      final weekly = (await h.collectionRepo
              .getWeeklyCollectionByDateRange(start, end))
          .dataOrNull!;
      expect(weekly, hasLength(1));
      expect(weekly.single.amountPaid, closeTo(550, 0.001));
      expect(weekly.single.collectedThisPeriod, closeTo(550, 0.001));
      expect(weekly.single.outstandingBalance, closeTo(1650, 0.001));
      expect(weekly.single.isPaidForPeriod, isTrue);
      expect(weekly.single.savingsBalance, 0.0);
    });

    test('cloud change-tracking: payment and savings rows get a valid sync timestamp',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 10,
          customCollectionAmount: 1000);

      await h.paymentRepo.createPayment(
        loanId: 'L1', customerId: 'C1', amount: 1500,
        method: PaymentMethod.cash, collector: 'Op',
        installmentDue: 1000,
      );

      final payments = await db.query('payments');
      final payStamp = payments.single['updated_at'] as String?;
      expect(payStamp, isNotNull);
      expect(payStamp, matches(_syncStampPattern),
          reason: 'payment must be cloud-replicable');

      final stx = await db.query('savings_transactions');
      final stxStamp = stx.single['updated_at'] as String?;
      expect(stxStamp, isNotNull);
      expect(stxStamp, matches(_syncStampPattern),
          reason: 'savings transaction must be cloud-replicable');

      final loans = await db.query('loans');
      expect(loans.single['updated_at'], isNotNull);
    });
  });

  group('repayment on scheduled vs non-payment dates (read-side attribution)', () {
    test('payment on a SCHEDULED date lights up that day; on a NON-payment date lights up the money date',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      // Fixed dates in the past: daily installments land on Mon..Fri
      // (2026-08-03 .. 2026-08-07), all weekdays — no weekends skipped.
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 5000, interestRate: 0, duration: 5,
          startDate: DateTime(2026, 8, 3));

      // On-installment payment.
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1000,
          method: PaymentMethod.cash, collector: 'Op');
      // Move that payment's recorded date onto an installment day.
      await db.update('payments', {'payment_date': '2026-08-04'},
          where: 'loan_id = ?', whereArgs: ['L1']);

      final onDate = (await h.collectionRepo
              .getDailyCollection(DateTime(2026, 8, 4)))
          .dataOrNull!;
      expect(onDate.single.amountPaid, closeTo(1000, 0.001),
          reason: 'payment on the scheduled date 2026-08-04 must show as collected');

      // Non-installment payment (Saturday 2026-08-08, after the schedule ends).
      final offPayment = await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 500,
          method: PaymentMethod.cash, collector: 'Op');
      await db.update('payments', {'payment_date': '2026-08-08'},
          where: 'id = ?', whereArgs: [offPayment.id]);

      final offDate = (await h.collectionRepo
              .getDailyCollection(DateTime(2026, 8, 8)))
          .dataOrNull!;
      expect(offDate, hasLength(1),
          reason: 'a non-installment payment day must still list the loan');
      expect(offDate.single.amountPaid, closeTo(500, 0.001),
          reason: 'collected on the money-arrival date, not the schedule');

      // The other days show their own money, nothing cross-contaminated.
      final otherDay = (await h.collectionRepo
              .getDailyCollection(DateTime(2026, 8, 6)))
          .dataOrNull!;
      expect(otherDay.single.amountPaid, 0.0);
    });

    test('late payment for an older missed installment attributes to the date money arrived (range view)',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 5000, interestRate: 0, duration: 5,
          startDate: DateTime(2026, 8, 3));

      final latePayment = await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1000,
          method: PaymentMethod.cash, collector: 'Op');
      // Paid late: money arrived 2026-08-10, well after the 08-03..08-07 dues.
      await db.update('payments', {'payment_date': '2026-08-10'},
          where: 'id = ?', whereArgs: [latePayment.id]);

      final range = (await h.collectionRepo.getCollectionsByDateRange(
              DateTime(2026, 8, 10), DateTime(2026, 8, 10)))
          .dataOrNull!;
      expect(range.single.amountPaid, closeTo(1000, 0.001),
          reason: 'money-arrival week must collect the late payment');

      final earlyRange = (await h.collectionRepo.getCollectionsByDateRange(
              DateTime(2026, 8, 3), DateTime(2026, 8, 7)))
          .dataOrNull!;
      expect(earlyRange.single.amountPaid, 0.0,
          reason: 'nothing was collected in the due week');
    });
  });

  group('reversal preserves the outstanding invariant (no double-count, no missed restore)', () {
    test('reversing a partial payment restores the exact outstanding and drops collected',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      final payment = await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 3000,
          method: PaymentMethod.cash, collector: 'Op');

      await h.paymentRepo.reversePayment(payment.id);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 10000,
          reason: 'outstanding must be fully restored');
      expect(loan['status'], 'active');

      final payments = await db.query('payments');
      expect(payments.single['status'], 'reversed');
      expect(payments.single['prior_loan_status'], 'active');

      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = DateTime(today.year, today.month, today.day, 23, 59, 59);
      final summary =
          (await h.reportRepo.getReportSummary(start, end)).dataOrNull!;
      expect(summary.totalCollected, 0.0,
          reason: 'reversed payments must not count as collected');

      final schedule = await h.scheduleRows('L1');
      expect(schedule.first['status'], 'pending');
      expect((schedule.first['paid_amount'] as num).toDouble(), 0.0);
    });

    test('reversing an overpayment refunds savings and restores only the loan-applied portion',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 10,
          customCollectionAmount: 1000);

      final payment = await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1500,
          method: PaymentMethod.cash, collector: 'Op',
          installmentDue: 1000);
      expect(await h.savingsBalance('C1'), 500);

      await h.paymentRepo.reversePayment(payment.id);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 10000,
          reason: 'exactly the 1000 applied to the loan is restored — NOT 1500');
      expect(loan['status'], 'active');
      expect(await h.savingsBalance('C1'), 0.0,
          reason: 'the 500 savings credit is refunded');
      expect(await paymentsStatusCount(db, 'reversed'), 1);
    });
  });

  group('clearLoanWithSavings (payment via savings withdrawal)', () {
    Future<void> seedSavings(Database db, double balance) async {
      await db.insert('savings_accounts', {
        'id': 'SA1', 'customer_id': 'C1', 'balance': balance,
        'created_at': '2026-08-01T00:00:00.000Z',
      });
    }

    test('clears the exact outstanding, debits savings, links the withdrawal',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 7000, interestRate: 0, duration: 5);
      await seedSavings(db, 8000);

      await h.paymentRepo.clearLoanWithSavings(loanId: 'L1', customerId: 'C1');

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 0.0);
      expect(loan['status'], 'completed');

      expect(await h.savingsBalance('C1'), 1000,
          reason: 'only the outstanding 7000 is withdrawn, 1000 stays saved');

      final payments = await db.query('payments');
      expect(payments, hasLength(1));
      expect(payments.single['payment_method'], 'savings');
      expect(payments.single['type'], 'full');
      expect(payments.single['prior_loan_status'], 'active');
      expect(payments.single['status'], 'completed');

      final stx = await db.query('savings_transactions');
      expect(stx, hasLength(1));
      expect(stx.single['type'], 'withdrawal');
      expect((stx.single['amount'] as num).toDouble(), 7000);
      expect(stx.single['reference_loan_payment_id'],
          payments.single['id'],
          reason: 'withdrawal must be linked so reversal can refund it');

      final schedule = await h.scheduleRows('L1');
      for (final row in schedule) {
        expect(row['status'], 'paid');
        expect((row['paid_amount'] as num).toDouble(),
            (row['amount'] as num).toDouble());
      }

      final summary = (await h.reportRepo.getReportSummary(
              DateTime.now().subtract(const Duration(days: 1)),
              DateTime.now()))
          .dataOrNull!;
      expect(summary.totalCollected, closeTo(7000, 0.001),
          reason: 'a savings clear still counts as collected (money rule)');
    });

    test('rejects insufficient savings without writing any row', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 7000, interestRate: 0, duration: 5);
      await seedSavings(db, 2000);

      await expectLater(
        h.paymentRepo.clearLoanWithSavings(loanId: 'L1', customerId: 'C1'),
        throwsException,
        reason: 'balance below outstanding must be rejected',
      );

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 7000);
      expect(loan['status'], 'active');
      expect(await h.savingsBalance('C1'), 2000);
      expect(await db.query('payments'), isEmpty);
      expect(await db.query('savings_transactions'), isEmpty);
    });

    test('rejects a completed loan', () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 7000, interestRate: 0, duration: 5);
      await seedSavings(db, 8000);

      await h.paymentRepo.clearLoanWithSavings(loanId: 'L1', customerId: 'C1');
      await expectLater(
        h.paymentRepo.clearLoanWithSavings(loanId: 'L1', customerId: 'C1'),
        throwsException,
        reason: 'a completed loan must not be cleared twice',
      );
      expect(await db.query('payments'), hasLength(1));
      expect(await h.savingsBalance('C1'), 1000);
    });

    test('reversal of a savings-cleared payment refunds savings and restores exact outstanding',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 7000, interestRate: 0, duration: 5);
      await seedSavings(db, 8000);

      await h.paymentRepo.clearLoanWithSavings(loanId: 'L1', customerId: 'C1');
      final payment = (await db.query('payments')).single;

      await h.paymentRepo.reversePayment(payment['id'] as String);

      final loan = await h.loanRow('L1');
      expect((loan['outstanding_balance'] as num).toDouble(), 7000,
          reason: 'the savings clear is reversed: outstanding returns');
      expect(loan['status'], 'active');

      expect(await h.savingsBalance('C1'), 8000,
          reason: 'the 7000 withdrawal is refunded, balance is conserved');

      final stx = await db.query('savings_transactions');
      expect(stx, hasLength(2));
      expect(
          stx.any((r) => r['type'] == 'deposit' &&
              (r['amount'] as num).toDouble() == 7000),
          isTrue,
          reason: 'a deposit row records the refund, keeping the balance honest');

      expect(await paymentsStatusCount(db, 'reversed'), 1);
    });
  });

  group('payment history ordering (P-1 regression)', () {
    test('getPaymentsForLoan orders newest-first within the same payment_date',
        () async {
      final db = await openFullSchemaDb();
      addTearDown(db.close);
      final h = _Harness(db);
      await h.seedCustomer('C1', 'ADA');
      await h.seedLoan(
          loanId: 'L1', customerId: 'C1', loanType: LoanType.daily,
          amount: 10000, interestRate: 0, duration: 5);

      // Three payments all recorded "today" (same date-only payment_date).
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1000,
          method: PaymentMethod.cash, collector: 'Op');
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1000,
          method: PaymentMethod.cash, collector: 'Op');
      await h.paymentRepo.createPayment(
          loanId: 'L1', customerId: 'C1', amount: 1000,
          method: PaymentMethod.cash, collector: 'Op');

      // Force a distinct created_at on the middle row so ordering is provable.
      final payments = await db.query('payments');
      final middle = payments[1];
      await db.update('payments', {'created_at': '2026-08-13T05:00:00.000Z'},
          where: 'id = ?', whereArgs: [middle['id']]);
      await db.update('payments',
          {'created_at': '2026-08-13T07:00:00.000Z'},
          where: 'id != ?', whereArgs: [middle['id']]);

      final history = await h.paymentRepo.getPaymentsForLoan('L1');
      expect(history, hasLength(3));
      expect(history.first.id, isNot(middle['id']),
          reason: 'the later 07:00 rows sort ahead of the 05:00 row');
      expect(history.first.createdAt?.toIso8601String().startsWith('2026-08-13T07'),
          isTrue);
      expect(history.last.id, middle['id'],
          reason: 'the earliest created_at sorts last within the same date');
    });
  });
}

Future<int> paymentsStatusCount(Database db, String status) async {
  final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM payments WHERE status = ?', [status]);
  return (rows.first['c'] as int?) ?? 0;
}
