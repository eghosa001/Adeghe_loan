import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/groups/data/group_repository.dart';
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
    return db;
  }

  Future<void> seedWeeklyInGroup(
    Database db,
    String loanId,
    String customerId,
    String name,
    String groupId,
    DateTime startDate,
  ) async {
    await db.insert('customer_groups', {'id': groupId, 'name': 'Group $groupId'});
    await db.insert('customers', {
      'id': customerId, 'full_name': name, 'phone': '0801', 'group_id': groupId,
      'guarantor_1_name': 'G', 'guarantor_1_phone': '0802',
    });
    final loan = Loan(
      id: loanId, customerId: customerId, loanType: LoanType.weekly,
      status: LoanStatus.active, amount: 2000, interestRate: 10,
      duration: 4, loanDate: DateTime(2026, 7, 20), repaymentStartDate: startDate,
      totalRepayment: 2200, outstandingBalance: 2200,
      installmentAmount: 550, expectedCompletionDate: DateTime(2026, 9, 1),
    );
    final amounts = CurrencyUtils.splitEvenly(2200, 4);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId, loanType: LoanType.weekly, startDate: startDate,
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

  Future<void> markInstallmentPaid(Database db, String loanId,
      int installmentNumber, double amount) async {
    await db.update(
      'repayment_schedule',
      {'status': 'paid', 'paid_amount': amount},
      where: 'loan_id = ? AND installment_number = ?',
      whereArgs: [loanId, installmentNumber],
    );
  }

  GroupRepository repo(Database db) =>
      GroupRepository(_FakeDatabaseService(db));

  Future<Map<String, double>> summary(Database db, DateTime date) async {
    return repo(db).getCollectionSummary('G1', date);
  }

  test(
      'a late payment shows as collected on the day the money arrived, not the '
      'missed installment day', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Weekly installments: Mon 07-27, Mon 08-03, Mon 08-10, Mon 08-17 (550).
    await seedWeeklyInGroup(db, 'L1', 'C1', 'Ada', 'G1', DateTime(2026, 7, 27));

    // Ada misses W1 (07-27); on Mon 08-10 she pays 550, clearing that old W1.
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-10');
    await markInstallmentPaid(db, 'L1', 1, 550);

    // The day the money arrived: 550 collected, today's own installment due.
    final paymentDay = await summary(db, DateTime(2026, 8, 10));
    expect(paymentDay['due'], closeTo(550.0, 0.001));
    expect(paymentDay['paid'], closeTo(550.0, 0.001));
    expect(paymentDay['remaining'], closeTo(0.0, 0.001));

    // The missed-installment day itself: scheduled then, but no money that day.
    final missedDay = await summary(db, DateTime(2026, 7, 27));
    expect(missedDay['due'], closeTo(550.0, 0.001));
    expect(missedDay['paid'], closeTo(0.0, 0.001));
    expect(missedDay['remaining'], closeTo(550.0, 0.001));
  });

  test(
      'a payment on a non-installment day counts as collected with no due, and '
      'remaining is clamped to zero', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyInGroup(db, 'L1', 'C1', 'Ada', 'G1', DateTime(2026, 7, 27));

    // Ada pays on Wed 08-12 — a day with no scheduled weekly installment.
    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-12');
    await markInstallmentPaid(db, 'L1', 1, 550);

    final result = await summary(db, DateTime(2026, 8, 12));
    expect(result['due'], closeTo(0.0, 0.001));
    expect(result['paid'], closeTo(550.0, 0.001));
    expect(result['remaining'], closeTo(0.0, 0.001));
  });

  test('enabled holiday installments are excluded from the group due total', () async {
    final db = await openDb();
    addTearDown(db.close);
    await seedWeeklyInGroup(db, 'L1', 'C1', 'Ada', 'G1', DateTime(2026, 7, 27));
    await db.insert('holidays', {
      'id': 'H1', 'name': 'Public Holiday', 'date': '2026-08-10',
      'is_recurring': 0, 'is_enabled': 1,
    });

    final result = await summary(db, DateTime(2026, 8, 10));
    expect(result['due'], closeTo(0.0, 0.001));
    expect(result['paid'], closeTo(0.0, 0.001));
    expect(result['remaining'], closeTo(0.0, 0.001));
  });

  test('only the group members are counted', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Ada in G1 (installments Mon 07-27 .. 08-17).
    await seedWeeklyInGroup(db, 'L1', 'C1', 'Ada', 'G1', DateTime(2026, 7, 27));
    // Bob in G2 (same due dates, must NOT leak into G1's summary).
    await seedWeeklyInGroup(db, 'L2', 'C2', 'Bob', 'G2', DateTime(2026, 7, 27));

    await insertPayment(db, 'L1', 'C1', 'P1', 550, '2026-08-10');
    await markInstallmentPaid(db, 'L1', 1, 550);

    final result = await summary(db, DateTime(2026, 8, 10));
    expect(result['due'], closeTo(550.0, 0.001));
    expect(result['paid'], closeTo(550.0, 0.001));
    expect(result['remaining'], closeTo(0.0, 0.001));
  });
}
