import 'package:sqflite_sqlcipher/sqflite.dart';

class DatabaseMigrations {
  DatabaseMigrations._();

  static Future<void> run(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _v2(db);
    if (oldVersion < 3) await _v3(db);
    if (oldVersion < 4) await _v4(db);
    if (oldVersion < 5) await _v5(db);
    if (oldVersion < 6) await _v6(db);
  }

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

  static Future<void> _v3(Database db) async {
    await db.execute(
        "ALTER TABLE documents ADD COLUMN original_name TEXT NOT NULL DEFAULT 'Document'");
    await db.execute(
        "ALTER TABLE documents ADD COLUMN mime_type TEXT NOT NULL DEFAULT 'application/octet-stream'");
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)');
  }

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

  static Future<void> _v5(Database db) async {
    await db.execute(
        "ALTER TABLE payments ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'");
  }

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
}
