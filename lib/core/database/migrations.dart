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
        await db.insert('savings_accounts', {
          'id': const Uuid().v4(),
          'customer_id': customerId,
          'balance': 0.0,
          'created_at': now,
        });
      }
    }
  }
}
