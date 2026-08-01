import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class DatabaseMigrations {
  DatabaseMigrations._();

  static Future<void> run(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _v2(db);
    if (oldVersion < 3) await _v3(db);
    if (oldVersion < 4) await _v4(db);
    if (oldVersion < 5) await _v5(db);
    if (oldVersion < 6) await _v6(db);
    if (oldVersion < 7) await _v7(db);
    if (oldVersion < 8) await _v8(db);
    if (oldVersion < 9) await _v9(db);
    if (oldVersion < 10) await _v10(db);
    if (oldVersion < 11) await _v11(db);
    if (oldVersion < 12) await _v12(db);
    if (oldVersion < 13) await _v13(db);
    if (oldVersion < 14) await _v14(db);
    if (oldVersion < 15) await _v15(db);
    if (oldVersion < 16) await _v16(db);
  }

  // v8 — remove monthly loan columns since monthly loans are not supported
  static Future<void> _v8(Database db) async {
    // Recreate the loans table without the monthly columns so this works on
    // SQLite versions older than 3.35.0 that do not support DROP COLUMN.
    await db.execute('''
      CREATE TABLE loans_new (
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
        repayment_frequency TEXT,
        repayment_day INTEGER,
        daily_payment REAL,
        total_repayment REAL NOT NULL,
        outstanding_balance REAL NOT NULL,
        expected_completion_date TEXT NOT NULL,
        collector TEXT,
        notes TEXT,
        status TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT INTO loans_new (
        id, customer_id, loan_type, amount, interest_rate, insurance_fee,
        commission, processing_fee, admin_fee, other_charges, loan_date,
        start_date, duration_days, repayment_frequency, repayment_day,
        daily_payment, total_repayment, outstanding_balance,
        expected_completion_date, collector, notes, status
      )
      SELECT
        id, customer_id,
        CASE WHEN loan_type = 'monthly' THEN 'weekly' ELSE loan_type END AS loan_type,
        amount, interest_rate, insurance_fee,
        commission, processing_fee, admin_fee, other_charges, loan_date,
        start_date, duration_days, repayment_frequency, repayment_day,
        daily_payment, total_repayment, outstanding_balance,
        expected_completion_date, collector, notes, status
      FROM loans
    ''');
    await db.execute('DROP TABLE loans');
    await db.execute('ALTER TABLE loans_new RENAME TO loans');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)');
  }

  // v9 — add weekly loan support columns
  static Future<void> _v9(Database db) async {
    await db.execute('ALTER TABLE loans ADD COLUMN duration_weeks INTEGER');
    await db.execute('ALTER TABLE loans ADD COLUMN weekly_payment REAL');
  }

  // v10 — add per-guarantor phone and address columns
  static Future<void> _v10(Database db) async {
    await db.execute('ALTER TABLE customers ADD COLUMN guarantor_1_phone TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN guarantor_1_address TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN guarantor_2_phone TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN guarantor_2_address TEXT');
  }

  // v11 — add type column to payments table
  static Future<void> _v11(Database db) async {
    await db.execute("ALTER TABLE payments ADD COLUMN type TEXT DEFAULT 'partial'");
  }

  // v12 — add custom_collection_amount column to loans table
  static Future<void> _v12(Database db) async {
    await db.execute("ALTER TABLE loans ADD COLUMN custom_collection_amount REAL");
  }

  // v14 — composite indexes on loans for loan_type filtering
  static Future<void> _v14(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_type_status ON loans(loan_type, status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_type_date ON loans(loan_type, loan_date)');
  }

  // v15 — migrate legacy 'monthly' loan rows to 'weekly' (monthly loans are not
  // supported and were invisible to daily/weekly aggregates), and record the
  // loan status that existed before a payment was applied so reversal can
  // restore it exactly.
  static Future<void> _v15(Database db) async {
    await db.execute(
        "UPDATE loans SET loan_type = 'weekly' WHERE loan_type = 'monthly'");
    await db.execute(
        'ALTER TABLE payments ADD COLUMN prior_loan_status TEXT');
  }

  // v16 — drop the dead repayment_day column (never written by the app) by
  // recreating the loans table without it. Mirrors the v8 table-recreate
  // approach so it works on SQLite versions older than 3.35.0 that do not
  // support DROP COLUMN.
  static Future<void> _v16(Database db) async {
    await db.execute('''
      CREATE TABLE loans_new (
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
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT INTO loans_new (
        id, customer_id, loan_type, amount, interest_rate, insurance_fee,
        commission, processing_fee, admin_fee, other_charges, loan_date,
        start_date, duration_days, duration_weeks, repayment_frequency,
        daily_payment, weekly_payment, total_repayment, outstanding_balance,
        expected_completion_date, custom_collection_amount, collector,
        notes, status
      )
      SELECT
        id, customer_id, loan_type, amount, interest_rate, insurance_fee,
        commission, processing_fee, admin_fee, other_charges, loan_date,
        start_date, duration_days, duration_weeks, repayment_frequency,
        daily_payment, weekly_payment, total_repayment, outstanding_balance,
        expected_completion_date, custom_collection_amount, collector,
        notes, status
      FROM loans
    ''');
    await db.execute('DROP TABLE loans');
    await db.execute('ALTER TABLE loans_new RENAME TO loans');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_type_status ON loans(loan_type, status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_type_date ON loans(loan_type, loan_date)');
  }

  // v13 — composite indexes for payments and repayment_schedule
  static Future<void> _v13(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_loan_date ON payments(loan_id, payment_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan_date ON repayment_schedule(loan_id, due_date)');
  }

  // v2 — add indexes for performance
  static Future<void> _v2(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(full_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_bvn ON customers(bvn)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_nin ON customers(nin)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)');
  }

  // v3 — add original_name and mime_type to documents table
  static Future<void> _v3(Database db) async {
    await db.execute(
        "ALTER TABLE documents ADD COLUMN original_name TEXT NOT NULL DEFAULT 'Document'");
    await db.execute(
        "ALTER TABLE documents ADD COLUMN mime_type TEXT NOT NULL DEFAULT 'application/octet-stream'");
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)');
  }

  // v4 — add repayment_schedule table
  static Future<void> _v4(Database db) async {
    await db.execute('''
      CREATE TABLE repayment_schedule (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        amount REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        paid_amount REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan ON repayment_schedule(loan_id)');
  }

  // v5 — add payment status column
  static Future<void> _v5(Database db) async {
    await db.execute(
        "ALTER TABLE payments ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'");
  }

  // v6 — add audit_logs table
  static Future<void> _v6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        user TEXT NOT NULL,
        action TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        details TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)');
  }

  // v7 — customer groups + savings accounts + savings transactions
  static Future<void> _v7(Database db) async {
    // Customer groups
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customer_groups_name ON customer_groups(name)');

    // Add group_id FK to customers
    await db.execute(
        'ALTER TABLE customers ADD COLUMN group_id TEXT REFERENCES customer_groups(id) ON DELETE SET NULL');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_group ON customers(group_id)');

    // Savings accounts (one per customer)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_accounts_customer ON savings_accounts(customer_id)');

    // Savings transaction ledger
    await db.execute('''
      CREATE TABLE IF NOT EXISTS savings_transactions (
        id TEXT PRIMARY KEY,
        savings_account_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_loan_payment_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (savings_account_id) REFERENCES savings_accounts(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_transactions_account ON savings_transactions(savings_account_id)');

    // Back-fill savings accounts for existing customers who predate this migration
    final existing = await db.query('customers', columns: ['id']);
    final now = DateTime.now().toIso8601String();
    for (final row in existing) {
      final customerId = row['id'] as String;
      final alreadyHas = await db.query(
        'savings_accounts',
        columns: ['id'],
        where: 'customer_id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (alreadyHas.isEmpty) {
        await db.insert(
          'savings_accounts',
          {
            'id': const Uuid().v4(),
            'customer_id': customerId,
            'balance': 0.0,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }
}
