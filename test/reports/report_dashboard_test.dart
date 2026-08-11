import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/reports/data/report_repository.dart';
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
        status TEXT NOT NULL,
        date_registered TEXT NOT NULL,
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
        payment_date TEXT NOT NULL,
        collector TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE savings_transactions (
        id TEXT PRIMARY KEY,
        savings_account_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_loan_payment_id TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    return db;
  }

  String day(int offset) =>
      AppDateUtils.formatForStorage(DateTime.now().add(Duration(days: offset)));

  String stamp(int offset, String time) => '${day(offset)}T$time';

  Future<void> seedCustomer(Database db, String id, String name,
      {int registeredOffset = -30, String status = 'active'}) async {
    await db.insert('customers', {
      'id': id,
      'full_name': name,
      'phone': '080$id',
      'status': status,
      'date_registered': day(registeredOffset),
    });
  }

  Future<void> seedActiveLoan(
    Database db,
    String loanId,
    String customerId,
    double amount,
    int offsetDays, {
    String loanType = 'daily',
  }) async {
    final due = day(offsetDays);
    await db.insert('loans', {
      'id': loanId,
      'customer_id': customerId,
      'loan_type': loanType,
      'amount': amount,
      'interest_rate': 0,
      'loan_date': day(-2),
      'start_date': day(-2),
      'total_repayment': amount,
      'outstanding_balance': amount,
      'expected_completion_date': due,
      'status': 'active',
      'collector': 'Kemi',
    });
    await db.insert('repayment_schedule', {
      'id': '$loanId-1',
      'loan_id': loanId,
      'installment_number': 1,
      'due_date': due,
      'amount': amount,
      'status': 'pending',
      'paid_amount': 0,
    });
  }

  ReportRepository repo(Database db) =>
      ReportRepository(_FakeDatabaseService(db));

  test('today collection follows the money rule (overpayments and reversed)',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedCustomer(db, 'C1', 'Ada');
    await seedActiveLoan(db, 'L1', 'C1', 2000, 0);

    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 1000,
      'status': 'completed',
      'payment_date': day(0),
      'collector': 'Kemi',
    });
    await db.insert('payments', {
      'id': 'P2',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 1500,
      'status': 'completed',
      'payment_date': day(0),
      'collector': 'Kemi',
    });
    await db.insert('savings_transactions', {
      'id': 'ST1',
      'savings_account_id': 'SA1',
      'type': 'overpayment',
      'amount': 500,
      'reference_loan_payment_id': 'P2',
      'created_at': stamp(0, '10:00:00.000Z'),
    });
    await db.insert('payments', {
      'id': 'P3',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 9999,
      'status': 'reversed',
      'payment_date': day(0),
      'collector': 'Kemi',
    });

    final result = await repo(db).getReportDashboard(
      DateTime.now().subtract(const Duration(days: 29)),
      DateTime.now(),
    );
    result.when(
      success: (d) {
        // 1000 + (1500 - 500 overpayment) = 2000; reversed 9999 excluded.
        expect(d.today.collectedAmount, closeTo(2000.0, 0.001));
        expect(d.today.paymentCount, 2);
        // Installment due today remains fully unpaid on the schedule.
        expect(d.today.dueToday, closeTo(2000.0, 0.001));
        expect(d.today.dueTodayLoans, 1);
        expect(d.today.topCollectors, hasLength(1));
        expect(d.today.topCollectors.first.amount, closeTo(2000.0, 0.001));
        expect(d.today.topCollectors.first.count, 2);
        expect(d.summary.totalCollected, closeTo(2000.0, 0.001));
      },
      failure: (f) => fail('dashboard query failed: $f'),
    );
  });

  test('overdue risk buckets loans by age and totals the unpaid amount',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedCustomer(db, 'C1', 'Ada');
    await seedCustomer(db, 'C2', 'Bola');

    await seedActiveLoan(db, 'L1', 'C1', 100, -3);
    await seedActiveLoan(db, 'L2', 'C1', 200, -10);
    await seedActiveLoan(db, 'L3', 'C2', 400, -20);
    await seedActiveLoan(db, 'L4', 'C2', 1000, 5);

    final result = await repo(db).getReportDashboard(
      DateTime.now().subtract(const Duration(days: 29)),
      DateTime.now(),
    );
    result.when(
      success: (d) {
        expect(d.overdue.overdueLoans, 3);
        expect(d.overdue.totalAmount, closeTo(700.0, 0.001));
        expect(d.overdue.buckets[0].loanCount, 1);
        expect(d.overdue.buckets[0].amount, closeTo(100.0, 0.001));
        expect(d.overdue.buckets[1].loanCount, 1);
        expect(d.overdue.buckets[1].amount, closeTo(200.0, 0.001));
        expect(d.overdue.buckets[2].loanCount, 1);
        expect(d.overdue.buckets[2].amount, closeTo(400.0, 0.001));
        expect(d.overdue.topAccounts.first.customerName, 'Bola');
        expect(d.overdue.topAccounts.first.amount, closeTo(400.0, 0.001));
      },
      failure: (f) => fail('dashboard query failed: $f'),
    );
  });

  test('savings and customer sections reflect balance, flows and counts',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedCustomer(db, 'C1', 'Ada');
    await seedCustomer(db, 'C2', 'Bola', registeredOffset: -1);
    await seedCustomer(db, 'C3', 'Eve', registeredOffset: 0,
        status: 'archived');

    await seedActiveLoan(db, 'L1', 'C1', 100, -3);
    await db.insert('savings_accounts', {
      'id': 'SA1',
      'customer_id': 'C1',
      'balance': 1500,
      'created_at': stamp(-30, '09:00:00.000Z'),
    });

    await db.insert('savings_transactions', {
      'id': 'T1',
      'savings_account_id': 'SA1',
      'type': 'deposit',
      'amount': 1000,
      'reference_loan_payment_id': null,
      'created_at': stamp(0, '10:00:00.000Z'),
    });
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 200,
      'status': 'completed',
      'payment_date': day(-2),
      'collector': 'Kemi',
    });
    await db.insert('savings_transactions', {
      'id': 'T2',
      'savings_account_id': 'SA1',
      'type': 'overpayment',
      'amount': 500,
      'reference_loan_payment_id': 'P1',
      'created_at': stamp(-2, '10:00:00.000Z'),
    });
    await db.insert('savings_transactions', {
      'id': 'T3',
      'savings_account_id': 'SA1',
      'type': 'withdrawal',
      'amount': 300,
      'reference_loan_payment_id': null,
      'created_at': stamp(0, '11:00:00.000Z'),
    });

    final result = await repo(db).getReportDashboard(
      DateTime.now().subtract(const Duration(days: 29)),
      DateTime.now(),
    );
    result.when(
      success: (d) {
        expect(d.savings.totalBalance, closeTo(1500.0, 0.001));
        expect(d.savings.inflow, closeTo(1500.0, 0.001));
        expect(d.savings.outflow, closeTo(300.0, 0.001));
        expect(d.customers.totalCustomers, 2);
        expect(d.customers.newInPeriod, 1);
        expect(d.customers.activeLoanCustomers, 1);
      },
      failure: (f) => fail('dashboard query failed: $f'),
    );
  });

  test('previous-period summary backs the deltas on the primary cards',
      () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedCustomer(db, 'C1', 'Ada');
    await seedActiveLoan(db, 'L1', 'C1', 2000, 0);

    // A payment 31 days ago is OUTSIDE the current 30-day range but INSIDE
    // the previous 30-day period, so the delta sees a real change.
    await db.insert('payments', {
      'id': 'P1',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 700,
      'status': 'completed',
      'payment_date': day(-31),
      'collector': 'Kemi',
    });

    final result = await repo(db).getReportDashboard(
      DateTime.now().subtract(const Duration(days: 29)),
      DateTime.now(),
    );
    result.when(
      success: (d) {
        expect(d.previousSummary.totalCollected, closeTo(700.0, 0.001));
        expect(d.summary.totalCollected, closeTo(0.0, 0.001));
      },
      failure: (f) => fail('dashboard query failed: $f'),
    );
  });
}
