import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/database/database_service.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/collection/data/collection_repository.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';
import 'package:loantrack/features/reports/services/export_manager.dart';
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

  Future<void> seed(
    Database db,
    String loanId,
    String customerId,
    String name,
    DateTime loanDate,
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
      duration: 4, loanDate: loanDate, repaymentStartDate: startDate,
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

  test('repro: export order vs disbursement date', () async {
    final db = await openDb();
    addTearDown(db.close);
    // Loans created out of disbursement-date order: loan_date (creation date)
    // differs from start_date, so the displayed disbursement date (start − 7)
    // does NOT follow loan_date. This reproduces the unsorted-export bug.
    //   Bravo:  loan 07-06, start 08-05 → disp 07-29
    //   Alpha:  loan 08-05, start 08-12 → disp 08-05
    //   Charlie: loan 07-20, start 08-19 → disp 08-12
    // loan_date order: Bravo, Charlie, Alpha (wrong); start_date order: Bravo, Alpha, Charlie.
    await seed(db, 'L1', 'C1', 'Alpha',
        DateTime(2026, 8, 5), DateTime(2026, 8, 12));
    await seed(db, 'L2', 'C2', 'Bravo',
        DateTime(2026, 7, 6), DateTime(2026, 8, 5));
    await seed(db, 'L3', 'C3', 'Charlie',
        DateTime(2026, 7, 20), DateTime(2026, 8, 19));

    final repo = CollectionRepository(_FakeDatabaseService(db));
    final result = await repo.getWeeklyCollectionByDateRange(
        DateTime(2026, 7, 1), DateTime(2026, 8, 31));
    result.when(
      success: (rows) {
        debugPrint('REPO ORDER:');
        for (final r in rows) {
          debugPrint('  ${r.customerName} loanDate=${r.loanDate} anchor=${r.paymentAnchorDate} disp=${r.disbursementDate}');
        }
        final bytes = ExportManager.buildWeeklyCollectionExcelBytes(
            rows, DateTime(2026, 8, 10));
        final decoded = Excel.decodeBytes(bytes);
        final sheet = decoded.tables[decoded.tables.keys.first]!;
        debugPrint('EXCEL DATA ROWS:');
        final names = <String>[];
        for (int r = 4; r < 4 + rows.length; r++) {
          final name = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value
              ?.toString();
          final disp = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r)).value
              ?.toString();
          debugPrint('  row $r: name=$name disp=$disp');
          names.add(name ?? '');
        }
        // Rows must be ordered by the DISPLAYED disbursement date.
        expect(names, ['Bravo', 'Alpha', 'Charlie']);
        final dispDates = rows.map((r) => r.disbursementDate).toList();
        expect(dispDates, List.of(dispDates)..sort());
      },
      failure: (f) => fail('query failed: $f'),
    );
  });
}
