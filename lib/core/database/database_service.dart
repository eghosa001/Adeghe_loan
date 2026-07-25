import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';
import '../security/secure_storage_service.dart';
import 'migrations.dart';

class DatabaseService {
  static const int _databaseVersion = 8;
  final SecureStorageService _secureStorage;

  DatabaseService(this._secureStorage);

  Database? _database;
  String? _databasePath;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<String> get databasePath async {
    if (_databasePath != null) return _databasePath!;
    final documentsDirectory = await getApplicationDocumentsDirectory();
    _databasePath = join(documentsDirectory.path, AppConstants.databaseName);
    return _databasePath!;
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, AppConstants.databaseName);
    final encryptionKey = await _secureStorage.getDatabaseKey();

    return await openDatabase(
      path,
      password: encryptionKey,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE business_profile (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        logo_path TEXT,
        address TEXT,
        phone TEXT,
        email TEXT,
        reg_no TEXT,
        owner_name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customer_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        passport_path TEXT,
        full_name TEXT NOT NULL,
        gender TEXT,
        dob TEXT,
        phone TEXT UNIQUE NOT NULL,
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
        guarantor_2_name TEXT,
        guarantor_phone TEXT,
        guarantor_address TEXT,
        guarantor_passport_path TEXT,
        nin TEXT UNIQUE,
        bvn TEXT UNIQUE,
        id_type TEXT,
        id_number TEXT,
        signature_path TEXT,
        date_registered TEXT NOT NULL,
        notes TEXT,
        status TEXT NOT NULL,
        credit_score REAL DEFAULT 0.0,
        group_id TEXT REFERENCES customer_groups(id) ON DELETE SET NULL
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
        status TEXT NOT NULL DEFAULT 'completed',
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE
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
        paid_amount REAL NOT NULL DEFAULT 0.0,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        loan_id TEXT,
        doc_type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        uploaded_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (loan_id) REFERENCES loans (id) ON DELETE CASCADE
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
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        user TEXT NOT NULL,
        action TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        details TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE savings_transactions (
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

    await _createIndexes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DatabaseMigrations.run(db, oldVersion, newVersion);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(full_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_bvn ON customers(bvn)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_nin ON customers(nin)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_group ON customers(group_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_accounts_customer ON savings_accounts(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_transactions_account ON savings_transactions(savings_account_id)');
  }
}
