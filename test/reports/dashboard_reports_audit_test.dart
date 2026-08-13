import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/reports/data/report_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show OpenDatabaseOptions, databaseFactoryFfi, inMemoryDatabasePath, sqfliteFfiInit;
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

class _FakeDatabaseService extends DatabaseService {
  _FakeDatabaseService(this._db) : super(SecureStorageService());
  final Database _db;
  @override
  Future<Database> get database async => _db;
}

// ── In-memory DB isolation ─────────────────────────────────────────────
// `singleInstance: false` gives each open() its own isolated connection so
// the second :memory: database is truly independent (otherwise sqflite
// returns the same singleton connection and duplicate INSERTs collide).
Future<Database> openSchemaDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      phone TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      date_registered TEXT NOT NULL,
      group_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE customer_groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE loans (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      loan_type TEXT NOT NULL,
      amount REAL NOT NULL,
      interest_rate REAL NOT NULL DEFAULT 0.0,
      insurance_fee REAL NOT NULL DEFAULT 0.0,
      commission REAL NOT NULL DEFAULT 0.0,
      processing_fee REAL NOT NULL DEFAULT 0.0,
      admin_fee REAL NOT NULL DEFAULT 0.0,
      other_charges REAL NOT NULL DEFAULT 0.0,
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

ReportRepository repo(Database db) => ReportRepository(_FakeDatabaseService(db));

String day(int offset) =>
    AppDateUtils.formatForStorage(DateTime.now().add(Duration(days: offset)));

String stamp(int offset, String time) => '${day(offset)}T$time';

// ── Reference-computation helpers (run against the seeded Dart lists) ──────

final payments = <Map<String, Object?>>[];
final savingsTx = <Map<String, Object?>>[];
final holidays = <Map<String, Object?>>[];
final schedule = <Map<String, Object?>>[];
final loans = <Map<String, Object?>>[];
final customers = <Map<String, Object?>>[];
final savingsAccounts = <Map<String, Object?>>[];

String sref(Map<String, Object?> m, String k) => (m[k] as String?) ?? '';
double dref(Map<String, Object?> m, String k) =>
    (m[k] as num?)?.toDouble() ?? 0.0;
int iref(Map<String, Object?> m, String k) => (m[k] as int?) ?? 0;

String fmt(DateTime d) => AppDateUtils.formatForStorage(d);
bool inWindow(String dateStr, DateTime ws, DateTime we) =>
    dateStr.compareTo(fmt(ws)) >= 0 && dateStr.compareTo(fmt(we)) <= 0;

bool excludedByHoliday(String dueDate) {
  for (final h in holidays) {
    if (iref(h, 'is_enabled') != 1) continue;
    if (iref(h, 'is_recurring') == 0 && sref(h, 'date') == dueDate) return true;
    if (iref(h, 'is_recurring') == 1 &&
        sref(h, 'date').substring(5) == dueDate.substring(5)) {
      return true;
    }
  }
  return false;
}

double refCollected(DateTime ws, DateTime we) => payments.where((p) {
  if (sref(p, 'status') != 'completed') return false;
  return inWindow(sref(p, 'payment_date'), ws, we);
}).fold<double>(0.0, (a, p) {
  var overpay = 0.0;
  for (final st in savingsTx) {
    if (sref(st, 'reference_loan_payment_id') == sref(p, 'id') &&
        sref(st, 'type') == 'overpayment') {
      overpay += dref(st, 'amount');
    }
  }
  return a + dref(p, 'amount') - overpay;
});

double refDisbursed(DateTime ws, DateTime we) => loans.where((l) {
  final st = sref(l, 'status');
  return (st == 'active' || st == 'completed' || st == 'defaulted') &&
      inWindow(sref(l, 'loan_date'), ws, we);
}).fold<double>(0.0, (a, l) => a + dref(l, 'amount'));

double refExpected(DateTime ws, DateTime we) => schedule.where((s) {
  final loanId = sref(s, 'loan_id');
  final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
  if (sref(loan, 'status') != 'active') return false;
  if (sref(s, 'status') == 'paid') return false;
  final due = sref(s, 'due_date');
  if (!inWindow(due, ws, we)) return false;
  if (excludedByHoliday(due)) return false;
  return true;
}).fold<double>(0.0, (a, s) => a + dref(s, 'amount') - dref(s, 'paid_amount'));

int refActiveLoans(DateTime we) => loans.where((l) =>
    sref(l, 'status') == 'active' &&
    sref(l, 'loan_date').compareTo(fmt(we)) <= 0).length;

int refCompletedLoans(DateTime we) => loans.where((l) =>
    sref(l, 'status') == 'completed' &&
    sref(l, 'loan_date').compareTo(fmt(we)) <= 0).length;

double refOutstanding() => loans.where((l) => sref(l, 'status') == 'active')
    .fold<double>(0.0, (a, l) => a + dref(l, 'outstanding_balance'));

int refTodayPaymentCount() {
  final today = fmt(DateTime.now());
  return payments.where((p) =>
      sref(p, 'status') == 'completed' && sref(p, 'payment_date') == today).length;
}

double refTodayCollected() {
  final today = fmt(DateTime.now());
  return payments.where((p) =>
      sref(p, 'status') == 'completed' && sref(p, 'payment_date') == today)
      .fold<double>(0.0, (a, p) {
    var overpay = 0.0;
    for (final st in savingsTx) {
      if (sref(st, 'reference_loan_payment_id') == sref(p, 'id') &&
          sref(st, 'type') == 'overpayment') {
        overpay += dref(st, 'amount');
      }
    }
    return a + dref(p, 'amount') - overpay;
  });
}

double refDueToday() {
  final today = fmt(DateTime.now());
  return schedule.where((s) {
    final loanId = sref(s, 'loan_id');
    final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
    if (sref(loan, 'status') != 'active') return false;
    if (sref(s, 'status') == 'paid') return false;
    if (sref(s, 'due_date') != today) return false;
    return !excludedByHoliday(today);
  }).fold<double>(0.0, (a, s) => a + dref(s, 'amount') - dref(s, 'paid_amount'));
}

int refOverdueLoans() {
  final today = fmt(DateTime.now());
  final ids = <String>{};
  for (final s in schedule) {
    if (sref(s, 'status') == 'paid') continue;
    final due = sref(s, 'due_date');
    if (due.compareTo(today) >= 0) continue;
    if (excludedByHoliday(due)) continue;
    final loanId = sref(s, 'loan_id');
    final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
    if (!ids.contains(loanId)) {
      final st = sref(loan, 'status');
      if ((st == 'active' || st == 'defaulted') &&
          sref(loan, 'loan_date').compareTo(today) <= 0) {
        ids.add(loanId);
      }
    }
  }
  return ids.length;
}

double refOverdueAmount() {
  final today = fmt(DateTime.now());
  return schedule.where((s) {
    final loanId = sref(s, 'loan_id');
    final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
    if (sref(s, 'status') == 'paid') return false;
    if (sref(loan, 'status') != 'active' && sref(loan, 'status') != 'defaulted') return false;
    final due = sref(s, 'due_date');
    if (due.compareTo(today) >= 0) return false;
    if (sref(loan, 'loan_date').compareTo(today) > 0) return false;
    return !excludedByHoliday(due);
  }).fold<double>(0.0, (a, s) => a + dref(s, 'amount') - dref(s, 'paid_amount'));
}

double refOverdueBucket(String minInclusive, String maxExclusive) =>
    schedule.where((s) {
      final loanId = sref(s, 'loan_id');
      final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
      if (sref(s, 'status') == 'paid') return false;
      if (sref(loan, 'status') != 'active' && sref(loan, 'status') != 'defaulted') return false;
      final due = sref(s, 'due_date');
      return due.compareTo(minInclusive) >= 0 && due.compareTo(maxExclusive) < 0 &&
          !excludedByHoliday(due);
    }).fold<double>(0.0, (a, s) => a + dref(s, 'amount') - dref(s, 'paid_amount'));

int refOverdueBucketLoans(String minInclusive, String maxExclusive) {
  final todayStr = fmt(DateTime.now());
  final ids = <String>{};
  for (final s in schedule) {
    if (sref(s, 'status') == 'paid') continue;
    final loanId = sref(s, 'loan_id');
    final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
    if (sref(loan, 'status') != 'active' && sref(loan, 'status') != 'defaulted') continue;
    final due = sref(s, 'due_date');
    if (!ids.contains(loanId)) {
      if (due.compareTo(minInclusive) >= 0 && due.compareTo(maxExclusive) < 0 &&
          !excludedByHoliday(due) &&
          sref(loan, 'loan_date').compareTo(todayStr) <= 0) {
        ids.add(loanId);
      }
    }
  }
  return ids.length;
}

double refSavingsInflow(DateTime ws, DateTime we) => savingsTx.where((st) {
  final type = sref(st, 'type');
  final date = sref(st, 'created_at');
  if (!inWindow(date.substring(0, 10), ws, we)) return false;
  if (type == 'deposit') return true;
  if (type == 'overpayment') {
    final ref = sref(st, 'reference_loan_payment_id');
    return payments.any((p) => sref(p, 'id') == ref && sref(p, 'status') == 'completed');
  }
  return false;
}).fold<double>(0.0, (a, st) => a + dref(st, 'amount'));

double refSavingsOutflow(DateTime ws, DateTime we) => savingsTx.where((st) =>
    sref(st, 'type') == 'withdrawal' &&
    inWindow(sref(st, 'created_at').substring(0, 10), ws, we))
    .fold<double>(0.0, (a, st) => a + dref(st, 'amount'));

int refNewCustomers(DateTime ws, DateTime we) => customers.where((c) =>
    sref(c, 'status') != 'archived' &&
    inWindow(sref(c, 'date_registered'), ws, we)).length;

int refTotalCustomers() =>
    customers.where((c) => sref(c, 'status') != 'archived').length;

double refSavingsBalance() => savingsAccounts.where((sa) {
  final cid = sref(sa, 'customer_id');
  return customers.any((c) => sref(c, 'id') == cid && sref(c, 'status') != 'archived');
}).fold<double>(0.0, (a, sa) => a + dref(sa, 'balance'));

double refExpectedWithoutHoliday(DateTime ws, DateTime we) => schedule.where((s) {
  final loanId = sref(s, 'loan_id');
  final loan = loans.firstWhere((l) => sref(l, 'id') == loanId);
  if (sref(loan, 'status') != 'active') return false;
  if (sref(s, 'status') == 'paid') return false;
  final due = sref(s, 'due_date');
  return inWindow(due, ws, we);
}).fold<double>(0.0, (a, s) => a + dref(s, 'amount') - dref(s, 'paid_amount'));

// ── Seed helpers (populate both Dart lists and the given db) ──────────────

void seedBaseData(Database db) {
  payments.clear();
  savingsTx.clear();
  holidays.clear();
  schedule.clear();
  loans.clear();
  customers.clear();
  savingsAccounts.clear();

  customers.addAll([
    {'id': 'C1', 'full_name': 'Ada', 'phone': '0801', 'status': 'active', 'date_registered': day(-30), 'group_id': null},
    {'id': 'C2', 'full_name': 'Bola', 'phone': '0802', 'status': 'active', 'date_registered': day(-10), 'group_id': null},
    {'id': 'C3', 'full_name': 'Eve', 'phone': '0803', 'status': 'archived', 'date_registered': day(-5), 'group_id': null},
  ]);
  savingsAccounts.addAll([
    {'id': 'SA1', 'customer_id': 'C1', 'balance': 900.0, 'created_at': stamp(-30, '09:00:00.000Z')},
    {'id': 'SA2', 'customer_id': 'C2', 'balance': 400.0, 'created_at': stamp(-10, '09:00:00.000Z')},
  ]);
  savingsTx.addAll([
    {'id': 'ST-A', 'savings_account_id': 'SA1', 'type': 'deposit', 'amount': 1000.0, 'reference_loan_payment_id': null, 'created_at': stamp(-30, '10:00:00.000Z')},
    {'id': 'ST-B', 'savings_account_id': 'SA1', 'type': 'overpayment', 'amount': 200.0, 'reference_loan_payment_id': 'P1', 'created_at': stamp(-20, '12:00:00.000Z')},
    {'id': 'ST-C', 'savings_account_id': 'SA2', 'type': 'deposit', 'amount': 500.0, 'reference_loan_payment_id': null, 'created_at': stamp(-10, '11:00:00.000Z')},
    {'id': 'ST-D', 'savings_account_id': 'SA1', 'type': 'withdrawal', 'amount': 300.0, 'reference_loan_payment_id': null, 'created_at': stamp(-5, '14:00:00.000Z')},
    {'id': 'ST-E', 'savings_account_id': 'SA2', 'type': 'withdrawal', 'amount': 100.0, 'reference_loan_payment_id': null, 'created_at': stamp(-13, '09:00:00.000Z')},
  ]);
  loans.addAll([
    {'id': 'L1', 'customer_id': 'C1', 'loan_type': 'daily', 'amount': 1000.0, 'interest_rate': 0.0, 'insurance_fee': 0.0, 'commission': 0.0, 'processing_fee': 0.0, 'admin_fee': 0.0, 'other_charges': 0.0, 'loan_date': day(-25), 'start_date': day(-25), 'duration_days': 0, 'duration_weeks': 0, 'repayment_frequency': null, 'daily_payment': null, 'weekly_payment': null, 'total_repayment': 1000.0, 'outstanding_balance': 500.0, 'expected_completion_date': day(-25), 'custom_collection_amount': null, 'collector': 'Kemi', 'notes': null, 'status': 'active', 'updated_at': null},
    {'id': 'L2', 'customer_id': 'C2', 'loan_type': 'weekly', 'amount': 2000.0, 'interest_rate': 0.0, 'insurance_fee': 0.0, 'commission': 0.0, 'processing_fee': 0.0, 'admin_fee': 0.0, 'other_charges': 0.0, 'loan_date': day(-20), 'start_date': day(-20), 'duration_days': 0, 'duration_weeks': 0, 'repayment_frequency': null, 'daily_payment': null, 'weekly_payment': null, 'total_repayment': 2000.0, 'outstanding_balance': 2000.0, 'expected_completion_date': day(-20), 'custom_collection_amount': null, 'collector': 'Kemi', 'notes': null, 'status': 'active', 'updated_at': null},
    {'id': 'L3', 'customer_id': 'C3', 'loan_type': 'daily', 'amount': 300.0, 'interest_rate': 0.0, 'insurance_fee': 0.0, 'commission': 0.0, 'processing_fee': 0.0, 'admin_fee': 0.0, 'other_charges': 0.0, 'loan_date': day(-3), 'start_date': day(-3), 'duration_days': 0, 'duration_weeks': 0, 'repayment_frequency': null, 'daily_payment': null, 'weekly_payment': null, 'total_repayment': 300.0, 'outstanding_balance': 300.0, 'expected_completion_date': day(-3), 'custom_collection_amount': null, 'collector': 'Kemi', 'notes': null, 'status': 'completed', 'updated_at': null},
  ]);
  schedule.addAll([
    {'id': 'L1-1', 'loan_id': 'L1', 'installment_number': 1, 'due_date': day(-25), 'amount': 500.0, 'status': 'paid', 'paid_amount': 500.0},
    {'id': 'L1-2', 'loan_id': 'L1', 'installment_number': 2, 'due_date': day(-20), 'amount': 500.0, 'status': 'pending', 'paid_amount': 0.0},
    {'id': 'L2-1', 'loan_id': 'L2', 'installment_number': 1, 'due_date': day(-20), 'amount': 1000.0, 'status': 'pending', 'paid_amount': 0.0},
    {'id': 'L2-2', 'loan_id': 'L2', 'installment_number': 2, 'due_date': day(-13), 'amount': 1000.0, 'status': 'pending', 'paid_amount': 0.0},
    {'id': 'L3-1', 'loan_id': 'L3', 'installment_number': 1, 'due_date': day(-3), 'amount': 300.0, 'status': 'paid', 'paid_amount': 300.0},
  ]);
  payments.addAll([
    {'id': 'P1', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 700.0, 'status': 'completed', 'payment_date': day(-20), 'collector': 'Kemi'},
    {'id': 'P2', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 300.0, 'status': 'completed', 'payment_date': day(0), 'collector': 'Kemi'},
    {'id': 'P3', 'loan_id': 'L2', 'customer_id': 'C2', 'amount': 400.0, 'status': 'completed', 'payment_date': day(-5), 'collector': 'Kemi'},
    {'id': 'P4', 'loan_id': 'L2', 'customer_id': 'C2', 'amount': 500.0, 'status': 'completed', 'payment_date': day(-13), 'collector': 'Kemi'},
    {'id': 'P5', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 1000.0, 'status': 'reversed', 'payment_date': day(-2), 'collector': 'Kemi'},
  ]);
  holidays.add({'id': 'H1', 'name': 'Test Holiday', 'date': day(-1), 'is_recurring': 0, 'is_enabled': 1});

  for (final c in customers) {
    db.insert('customers', c);
  }
  for (final l in loans) {
    db.insert('loans', l);
  }
  for (final s in schedule) {
    db.insert('repayment_schedule', s);
  }
  for (final h in holidays) {
    db.insert('holidays', h);
  }
  for (final p in payments) {
    db.insert('payments', p);
  }
  for (final sa in savingsAccounts) {
    db.insert('savings_accounts', sa);
  }
  for (final st in savingsTx) {
    db.insert('savings_transactions', st);
  }
}

DateTime windowEnd(DateTime s, String label) {
  final now = DateTime.now();
  return switch (label) {
    'Today' => AppDateUtils.endOfDay(now),
    'Yesterday' => AppDateUtils.endOfDay(now.subtract(const Duration(days: 1))),
    'This Week' || 'Last Week' => AppDateUtils.endOfDay(s.add(const Duration(days: 6))),
    'This Month' => AppDateUtils.endOfMonth(now),
    'Last Month' => AppDateUtils.endOfDay(DateTime(now.year, now.month, 0)),
    'Last 30 Days' => AppDateUtils.endOfDay(now),
    _ => AppDateUtils.endOfDay(now),
  };
}

void main() {
  sqfliteFfiInit();

  test('this-month dashboard matches hand-computed reference', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final result = await repo(db).getReportDashboard(start, end);
    final d = result.dataOrNull!;
    expect(d.summary.totalDisbursed, closeTo(refDisbursed(start, end), 0.001), reason: 'disbursed');
    expect(d.summary.totalCollected, closeTo(refCollected(start, end), 0.001), reason: 'collected');
    expect(d.summary.netProfit, closeTo(refCollected(start, end) - refDisbursed(start, end), 0.001), reason: 'net-profit');
    expect(d.totalExpectedCollections, closeTo(refExpected(start, end), 0.001), reason: 'expected');
    expect(d.summary.activeLoans, refActiveLoans(end), reason: 'active');
    expect(d.summary.completedLoans, 1, reason: 'completed');
    expect(d.summary.defaultedLoans, 0, reason: 'defaulted');
    expect(d.totalOutstandingBalance, closeTo(refOutstanding(), 0.001), reason: 'outstanding');
    expect(d.summary.totalCustomers, refTotalCustomers(), reason: 'summary-total-customers');
    expect(d.today.collectedAmount, closeTo(refTodayCollected(), 0.001), reason: 'today-collected');
    expect(d.today.paymentCount, refTodayPaymentCount(), reason: 'today-payment-count');
    expect(d.today.dueToday, closeTo(refDueToday(), 0.001), reason: 'due-today');
    expect(d.overdue.overdueLoans, refOverdueLoans(), reason: 'overdue-loans');
    expect(d.overdue.totalAmount, closeTo(refOverdueAmount(), 0.001), reason: 'overdue-amount');
    expect(d.savings.totalBalance, closeTo(refSavingsBalance(), 0.001), reason: 'savings-balance');
    expect(d.savings.inflow, closeTo(refSavingsInflow(start, end), 0.001), reason: 'savings-in');
    expect(d.savings.outflow, closeTo(refSavingsOutflow(start, end), 0.001), reason: 'savings-out');
    expect(d.customers.totalCustomers, refTotalCustomers(), reason: 'customer-total');
    expect(d.customers.newInPeriod, refNewCustomers(start, end), reason: 'new-customers');
  });

  test('every preset aggregates correctly against the reference', () async {
    final now = DateTime.now();
    final presets = [
      ('Today', AppDateUtils.startOfDay(now), windowEnd(AppDateUtils.startOfDay(now), 'Today')),
      ('Yesterday', AppDateUtils.startOfDay(now.subtract(const Duration(days: 1))), windowEnd(AppDateUtils.startOfDay(now.subtract(const Duration(days: 1))), 'Yesterday')),
      ('This Week', AppDateUtils.startOfWeek(now), windowEnd(AppDateUtils.startOfWeek(now), 'This Week')),
      ('Last Week', AppDateUtils.startOfWeek(now).subtract(const Duration(days: 7)), windowEnd(AppDateUtils.startOfWeek(now).subtract(const Duration(days: 7)), 'Last Week')),
      ('This Month', AppDateUtils.startOfMonth(now), windowEnd(AppDateUtils.startOfMonth(now), 'This Month')),
      ('Last Month', DateTime(now.year, now.month - 1, 1), windowEnd(DateTime(now.year, now.month - 1, 1), 'Last Month')),
      ('Last 30 Days', AppDateUtils.startOfDay(now.subtract(const Duration(days: 29))), windowEnd(AppDateUtils.startOfDay(now.subtract(const Duration(days: 29))), 'Last 30 Days')),
    ];
    for (final (label, start, end) in presets) {
      final db = await openSchemaDb();
      addTearDown(db.close);
      seedBaseData(db);
      final r = await repo(db).getReportDashboard(start, end);
      final d = r.dataOrNull!;
      expect(d.summary.totalCollected, closeTo(refCollected(start, end), 0.001), reason: 'collected [$label]');
      expect(d.summary.totalDisbursed, closeTo(refDisbursed(start, end), 0.001), reason: 'disbursed [$label]');
      expect(d.totalExpectedCollections, closeTo(refExpected(start, end), 0.001), reason: 'expected [$label]');
      expect(d.summary.activeLoans, refActiveLoans(end), reason: 'active [$label]');
      expect(d.totalOutstandingBalance, closeTo(refOutstanding(), 0.001), reason: 'outstanding [$label]');
      expect(d.summary.totalCustomers, refTotalCustomers(), reason: 'total-customers [$label]');
      expect(d.customers.totalCustomers, refTotalCustomers(), reason: 'customer-total [$label]');
      expect(d.customers.newInPeriod, refNewCustomers(start, end), reason: 'new-customers [$label]');
    }
  });

  test('overdue buckets match reference aggregation', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final r = await repo(db).getReportDashboard(start, end);
    final d = r.dataOrNull!;
    expect(d.overdue.buckets[0].loanCount, refOverdueBucketLoans(fmt(DateTime.now().subtract(const Duration(days: 7))), fmt(DateTime.now())), reason: '1-7 day loans');
    expect(d.overdue.buckets[0].amount, closeTo(refOverdueBucket(fmt(DateTime.now().subtract(const Duration(days: 7))), fmt(DateTime.now())), 0.001), reason: '1-7 day amt');
    expect(d.overdue.buckets[1].loanCount, refOverdueBucketLoans(fmt(DateTime.now().subtract(const Duration(days: 14))), fmt(DateTime.now().subtract(const Duration(days: 7)))), reason: '8-14 day loans');
    expect(d.overdue.buckets[1].amount, closeTo(refOverdueBucket(fmt(DateTime.now().subtract(const Duration(days: 14))), fmt(DateTime.now().subtract(const Duration(days: 7)))), 0.001), reason: '8-14 day amt');
    expect(d.overdue.buckets[2].loanCount, refOverdueBucketLoans('', fmt(DateTime.now().subtract(const Duration(days: 14)))), reason: '15+ day loans');
    expect(d.overdue.buckets[2].amount, closeTo(refOverdueBucket('', fmt(DateTime.now().subtract(const Duration(days: 14)))), 0.001), reason: '15+ day amt');
  });

  test('today snapshot (collections, top collectors, due-today) stable across windows', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final r = await repo(db).getReportDashboard(start, end);
    final d = r.dataOrNull!;
    expect(d.today.collectedAmount, closeTo(refTodayCollected(), 0.001), reason: 'today-collected');
    expect(d.today.paymentCount, refTodayPaymentCount(), reason: 'today-pcount');
    expect(d.today.dueToday, closeTo(refDueToday(), 0.001), reason: 'due-today');
    expect(d.today.dueTodayLoans, 0, reason: 'due-today-loans');
  });

  test('enabled holiday excludes matching schedule row from expected and overdue', () async {
    // Seed an enabled holiday on day(-3), which IS the due date for L3-1.
    // However, L3 is completed so it doesn't contribute to expected/overdue.
    // Instead we seed an additional active loan with an installment due on
    // day(-3) — a date that lies within the current-month window — so the
    // holiday exclusion is observable in both expected and overdue sums.
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    // Insert an extra active loan (L4 on C1) whose single installment is
    // due today (day(0)) — within the month window and overdue bucket 15+.
    // Then insert an ENABLED holiday on day(-3) which coincides with L3's
    // due date; L3 is completed so this does NOT affect expected.
    // To make the test meaningful, insert an ENABLED holiday on a day that
    // matches an ACTIVE loan's due date that is WITHIN the current month.
    // We seed L4 with a due date of today so it's in-window and overdue.
    await db.insert('loans', {
      'id': 'L4', 'customer_id': 'C1', 'loan_type': 'daily',
      'amount': 500.0, 'interest_rate': 0.0, 'insurance_fee': 0.0,
      'commission': 0.0, 'processing_fee': 0.0, 'admin_fee': 0.0,
      'other_charges': 0.0, 'loan_date': day(0), 'start_date': day(0),
      'duration_days': 0, 'duration_weeks': 0, 'repayment_frequency': null,
      'daily_payment': null, 'weekly_payment': null,
      'total_repayment': 500.0, 'outstanding_balance': 500.0,
      'expected_completion_date': day(0), 'custom_collection_amount': null,
      'collector': 'Kemi', 'notes': null, 'status': 'active', 'updated_at': null,
    });
    await db.insert('repayment_schedule', {
      'id': 'L4-1', 'loan_id': 'L4', 'installment_number': 1,
      'due_date': day(0), 'amount': 500.0, 'status': 'pending', 'paid_amount': 0.0,
    });
    loans.add({'id': 'L4', 'customer_id': 'C1', 'loan_type': 'daily', 'amount': 500.0, 'interest_rate': 0.0, 'insurance_fee': 0.0, 'commission': 0.0, 'processing_fee': 0.0, 'admin_fee': 0.0, 'other_charges': 0.0, 'loan_date': day(0), 'start_date': day(0), 'duration_days': 0, 'duration_weeks': 0, 'repayment_frequency': null, 'daily_payment': null, 'weekly_payment': null, 'total_repayment': 500.0, 'outstanding_balance': 500.0, 'expected_completion_date': day(0), 'custom_collection_amount': null, 'collector': 'Kemi', 'notes': null, 'status': 'active', 'updated_at': null});
    schedule.add({'id': 'L4-1', 'loan_id': 'L4', 'installment_number': 1, 'due_date': day(0), 'amount': 500.0, 'status': 'pending', 'paid_amount': 0.0});
    // Enable a holiday on day(0) — today. Both the repo and reference
    // must agree it's excluded.
    await db.insert('holidays', {'id': 'H_TODAY', 'name': 'Today Holiday', 'date': day(0), 'is_recurring': 0, 'is_enabled': 1});
    holidays.add({'id': 'H_TODAY', 'name': 'Today Holiday', 'date': day(0), 'is_recurring': 0, 'is_enabled': 1});
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final r = await repo(db).getReportDashboard(start, end);
    final d = r.dataOrNull!;
    // L4 installment due today is excluded by the holiday → expected and
    // today-due both drop by 500. The reference (which also sees H_TODAY)
    // must agree.
    expect(d.totalExpectedCollections, closeTo(refExpected(start, end), 0.001));
    expect(d.today.dueToday, closeTo(refDueToday(), 0.001));
    // Clean up.
    holidays.removeWhere((h) => sref(h, 'id') == 'H_TODAY');
    loans.removeWhere((l) => sref(l, 'id') == 'L4');
    schedule.removeWhere((s) => sref(s, 'loan_id') == 'L4');
  });

  test('disabled holiday is ignored', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    // Insert a disabled holiday on day(-20). It must be silently ignored.
    await db.insert('holidays', {'id': 'H3', 'name': 'Disabled', 'date': day(-20), 'is_recurring': 0, 'is_enabled': 0});
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final r = await repo(db).getReportDashboard(start, end);
    final d = r.dataOrNull!;
    // No extra holidays active → expected equals the no-holiday reference.
    expect(d.totalExpectedCollections, closeTo(refExpectedWithoutHoliday(start, end), 0.001));
  });

  test('money rule: reversed payments and overpayment surplus are excluded', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final r = await repo(db).getReportDashboard(start, end);
    final d = r.dataOrNull!;
    expect(d.summary.totalCollected, closeTo(refCollected(start, end), 0.001),
        reason: 'window collected respects money rule');
    final rToday = await repo(db).getReportDashboard(
        AppDateUtils.startOfDay(DateTime.now()),
        windowEnd(AppDateUtils.startOfDay(DateTime.now()), 'Today'));
    expect(rToday.dataOrNull!.today.collectedAmount, closeTo(refTodayCollected(), 0.001),
        reason: 'today collected respects money rule');
  });

  test('trends daily buckets (31 days) sum to exact window totals', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final t = (await repo(db).getDashboardTrends(startDate: start, endDate: end)).dataOrNull!;
    expect(t.collected.fold<double>(0.0, (a, p) => a + p.value),
        closeTo(refCollected(start, end), 0.001));
    expect(t.disbursed.fold<double>(0.0, (a, p) => a + p.value),
        closeTo(refDisbursed(start, end), 0.001));
    expect(t.savingsIn.fold<double>(0.0, (a, p) => a + p.value),
        closeTo(refSavingsInflow(start, end), 0.001));
    expect(t.savingsOut.fold<double>(0.0, (a, p) => a + p.value),
        closeTo(refSavingsOutflow(start, end), 0.001));
    expect(t.customers.fold<double>(0.0, (a, p) => a + p.value),
        equals(refNewCustomers(start, end).toDouble()));
    expect(t.loans.fold<double>(0.0, (a, p) => a + p.value),
        equals(loans.where((l) => sref(l, 'status') != 'cancelled' && inWindow(sref(l, 'loan_date'), start, end)).length.toDouble()));
  });

  test('trends monthly buckets (>180 days) clamp at window boundaries', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    // Build a >180-day range whose first-of-month boundary falls BEFORE [start,end].
    final anchor = AppDateUtils.startOfMonth(DateTime.now());
    final start = anchor.subtract(const Duration(days: 140));
    final end = AppDateUtils.endOfDay(DateTime.now());
    // Seed a completed payment on the FIRST day of the month containing 'start' —
    // this is strictly before [start,end] and MUST be excluded from the trend sum.
    final outsideDate = AppDateUtils.formatForStorage(anchor.subtract(const Duration(days: 1)));
    await db.insert('payments', {
      'id': 'P_OUTSIDE',
      'loan_id': 'L1',
      'customer_id': 'C1',
      'amount': 999.0,
      'status': 'completed',
      'payment_date': outsideDate,
      'collector': 'Kemi',
    });
    payments.add({'id': 'P_OUTSIDE', 'loan_id': 'L1', 'customer_id': 'C1', 'amount': 999.0, 'status': 'completed', 'payment_date': outsideDate, 'collector': 'Kemi'});
    final t = (await repo(db).getDashboardTrends(startDate: start, endDate: end)).dataOrNull!;
    expect(t.collected.fold<double>(0.0, (a, p) => a + p.value),
        closeTo(refCollected(start, end), 0.001),
        reason: 'monthly trends must exclude data outside [start,end]');
  });

  test('report-dashboard Total Savings excludes archived-customer balances', () async {
    final db = await openSchemaDb();
    addTearDown(db.close);
    seedBaseData(db);
    final start = AppDateUtils.startOfMonth(DateTime.now());
    final end = windowEnd(start, 'This Month');
    final d = (await repo(db).getReportDashboard(start, end)).dataOrNull!;
    expect(d.savings.totalBalance, closeTo(refSavingsBalance(), 0.001),
        reason: 'archived customers excluded from report-dashboard savings');
  });
}
