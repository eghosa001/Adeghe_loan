import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../cloud/sync_timestamps.dart';

class DatabaseMigrations {
  DatabaseMigrations._();

  static Future<void> run(Database db, int oldVersion, int newVersion) async {
    // Each migration runs only when the installed schema predates it AND the
    // upgrade target includes it. Production passes newVersion = the latest
    // version so every pending migration runs; tests can migrate to an
    // intermediate version without executing later, heavier migrations.
    bool pending(int n) => oldVersion < n && n <= newVersion;
    if (pending(2)) await _v2(db);
    if (pending(3)) await _v3(db);
    if (pending(4)) await _v4(db);
    if (pending(5)) await _v5(db);
    if (pending(6)) await _v6(db);
    if (pending(7)) await _v7(db);
    if (pending(8)) await _v8(db);
    if (pending(9)) await _v9(db);
    if (pending(10)) await _v10(db);
    if (pending(11)) await _v11(db);
    if (pending(12)) await _v12(db);
    if (pending(13)) await _v13(db);
    if (pending(14)) await _v14(db);
    if (pending(15)) await _v15(db);
    if (pending(16)) await _v16(db);
    if (pending(17)) await _v17(db);
    if (pending(18)) await _v18(db);
    if (pending(19)) await _v19(db);
    if (pending(20)) await _v20(db);
    if (pending(21)) await _v21(db);
    if (pending(22)) await _v22(db);
    if (pending(23)) await _v23(db);
  }

  /// v20 — indexes backing the money-rule join and common date-range filters.
  /// The money rule's `LEFT JOIN savings_transactions st ON
  /// st.reference_loan_payment_id = p.id AND st.type = 'overpayment'` runs in
  /// every payment aggregate (dashboard, reports, collection, statements);
  /// without an index it full-scans savings_transactions per payment row. The
  /// other indexes serve per-customer payment history, global date-range
  /// filters, the holiday `NOT EXISTS` subquery, and the documents loan
  /// cascade. Fresh installs get these from `_createIndexes`.
  static Future<void> _v20(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_txns_ref_payment ON savings_transactions(reference_loan_payment_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_savings_txns_created ON savings_transactions(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_holidays_date ON holidays(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_documents_loan ON documents(loan_id)');
  }

  /// v21 — drop the `customers` column-level UNIQUE constraints and replace
  /// them with PARTIAL unique indexes that only apply to non-archived rows.
  /// `phone`/`nin`/`bvn` were `TEXT UNIQUE` in the table DDL, so archiving a
  /// customer permanently blocked re-registering that person (the repository
  /// check already excludes archived rows, but the DB constraint still fired
  /// `UNIQUE constraint failed` → generic "Unable to save customer"). SQLite
  /// cannot drop a column UNIQUE via ALTER, so the table is recreated (same
  /// pattern as v16). Existing rows cannot violate the partial indexes because
  /// the old UNIQUE constraints already forced all non-null values unique.
  static Future<void> _v21(Database db) async {
    await db.execute('''
      CREATE TABLE customers_new (
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
    ''');
    await db.execute('''
      INSERT INTO customers_new (
        id, passport_path, full_name, gender, dob, phone, alt_phone, email,
        residential_address, business_address, occupation, employer,
        marital_status, nationality, state, lga, next_of_kin,
        next_of_kin_relation, next_of_kin_phone, guarantor_1_name,
        guarantor_1_phone, guarantor_1_address, guarantor_2_name,
        guarantor_2_phone, guarantor_2_address, guarantor_passport_path, nin,
        bvn, id_type, id_number, signature_path, date_registered, notes,
        status, credit_score, group_id, updated_at
      )
      SELECT
        id, passport_path, full_name, gender, dob, phone, alt_phone, email,
        residential_address, business_address, occupation, employer,
        marital_status, nationality, state, lga, next_of_kin,
        next_of_kin_relation, next_of_kin_phone, guarantor_1_name,
        guarantor_1_phone, guarantor_1_address, guarantor_2_name,
        guarantor_2_phone, guarantor_2_address, guarantor_passport_path, nin,
        bvn, id_type, id_number, signature_path, date_registered, notes,
        status, credit_score, group_id, updated_at
      FROM customers
    ''');
    await db.execute('DROP TABLE customers');
    await db.execute('ALTER TABLE customers_new RENAME TO customers');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(full_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_group ON customers(group_id)');
    await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_unique ON customers(phone) WHERE status != 'archived'");
    await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_nin_unique ON customers(nin) WHERE status != 'archived'");
    await db.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_bvn_unique ON customers(bvn) WHERE status != 'archived'");
    // Recreate the v17 change-tracking triggers: the DROP TABLE above destroyed
    // trg_customers_ins/upd/del (SQLite drops a table's triggers with it), so
    // without this, customer writes on upgraded devices would never stamp
    // `updated_at` or record tombstones and customer sync would silently stop.
    await createSyncTriggersForTable(db, 'customers');
  }

  /// v22 — normalize existing customer names to ALL CAPS (owner request
  /// 2026-08-08). New names are already normalized at the repository boundary
  /// (`CustomerRepository.save`) and on cloud pull; this migration uppercases
  /// rows written before that so legacy data matches everywhere it renders
  /// (screens, reports, collection sheets, statements, documents). The v17
  /// `trg_customers_upd` trigger stamps `updated_at`, so renamed rows reach
  /// the cloud on the next sync.
  static Future<void> _v22(Database db) async {
    await db.execute('''
      UPDATE customers SET
        full_name = UPPER(TRIM(full_name)),
        next_of_kin = CASE WHEN next_of_kin IS NULL THEN NULL ELSE UPPER(TRIM(next_of_kin)) END,
        guarantor_1_name = CASE WHEN guarantor_1_name IS NULL THEN NULL ELSE UPPER(TRIM(guarantor_1_name)) END,
        guarantor_2_name = CASE WHEN guarantor_2_name IS NULL THEN NULL ELSE UPPER(TRIM(guarantor_2_name)) END
    ''');
  }

  /// v23 — backfill `updated_at` on replicated rows that still have none (live
  /// fix 2026-08-11). v17 stamped rows that predated it, but a row written by a
  /// path where the stamp trigger never ran keeps a NULL `updated_at` forever:
  /// the push sends it as an explicit NULL (`updated_at > ? OR updated_at IS
  /// NULL`), the cloud stores NULL, and the other device's pull guard
  /// (`isSaneCloudRow`) rejects a row with no valid sync timestamp — so that
  /// payment/savings row never reaches the other device and its totals stay
  /// different forever (observed live: 7 payments + 1 savings transaction in
  /// the cloud that the phone never received). Backfilling the NULL rows with a
  /// valid `syncTimestamp()` makes the next push send a pullable row. Only the
  /// replicated tables are touched (repayment_schedule is a derived local cache
  /// and never replicated; audit_logs/settings are device-local).
  static Future<void> _v23(Database db) async {
    final now = syncTimestamp();
    await db.execute(
        'UPDATE business_profile SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE customer_groups SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE customers SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE loans SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE payments SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE savings_accounts SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE savings_transactions SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE documents SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE holidays SET updated_at = ? WHERE updated_at IS NULL', [now]);
  }

  /// Tables that get cloud-sync change tracking (updated_at stamping +
  /// tombstone triggers), in parent-before-child dependency order. NOTE: this
  /// list drives `createSyncSchema` ONLY; the sync service keeps its own
  /// replication list (`_tables` in `cloud_sync_service.dart`) which is a
  /// strict subset (audit_logs/settings are tracked locally but never pushed,
  /// and `repayment_schedule` is a derived cache — tracked in v17, dropped in
  /// v19 — and never replicated).
  static const List<String> _syncTables = [
    'business_profile',
    'customer_groups',
    'customers',
    'loans',
    'payments',
    'savings_accounts',
    'savings_transactions',
    'documents',
    'holidays',
    'audit_logs',
    'settings',
  ];

  static const Map<String, String> _syncTablePrimaryKeys = {
    'business_profile': 'id',
    'customer_groups': 'id',
    'customers': 'id',
    'loans': 'id',
    'payments': 'id',
    'savings_accounts': 'id',
    'savings_transactions': 'id',
    'documents': 'id',
    'holidays': 'id',
    'audit_logs': 'id',
    'settings': 'key',
  };

  /// v19 — stop change-tracking `repayment_schedule`. The schedule is a derived
  /// cache recomputed on every device from synced source data (loans +
  /// payments + savings + holidays), so its rows are never replicated. Drop its
  /// stamp/tombstone triggers (created in v17) and purge its stale tombstones.
  /// The `updated_at` column itself is left in place (harmless, and dropping
  /// it would require a table recreate).
  static Future<void> _v19(Database db) async {
    for (final name in const ['ins', 'upd', 'del']) {
      await db.execute('DROP TRIGGER IF EXISTS trg_repayment_schedule_$name');
    }
    await db.execute(
        'DELETE FROM sync_tombstones WHERE deleted_table = ?',
        ['repayment_schedule']);
  }

  /// v18 — add a client-side idempotency key to payments so a retried/double
  /// submission of the same logical payment cannot create a duplicate.
  /// `createPayment` checks this key inside its serialized transaction before
  /// applying a payment and CAS-guards the loan balance, so the column alone
  /// (plus the repository check) provides the dedupe; a DB UNIQUE index is
  /// deliberately not added here because the schema guard's parser only
  /// recognises `CREATE INDEX` (not `CREATE UNIQUE INDEX`).
  static Future<void> _v18(Database db) async {
    // Idempotent guard: an early build shipped the fresh-install DDL with
    // `client_request_id` already present while `_databaseVersion` was still
    // 17, so databases created by that build reach v18 with the column already
    // in place — a bare ALTER throws "duplicate column name" and SQLite rolls
    // the whole upgrade back on every launch. SQLite has no
    // `ADD COLUMN IF NOT EXISTS`, so probe `PRAGMA table_info` first.
    final columns = await db.rawQuery('PRAGMA table_info(payments)');
    final hasColumn = columns.any((c) => c['name'] == 'client_request_id');
    if (!hasColumn) {
      await db
          .execute('ALTER TABLE payments ADD COLUMN client_request_id TEXT');
    }
  }

  /// v17 — add cloud-sync change tracking.
  ///
  /// Adds an `updated_at` column (local ISO-8601 UTC timestamp, stamped by
  /// triggers on every non-sync write) to every replicated table, plus the
  /// `sync_flags` / `sync_meta` / `sync_tombstones` bookkeeping tables and the
  /// stamp/tombstone triggers. Rows created before this migration get their
  /// `updated_at` back-filled so the first push uploads the whole database.
  static Future<void> _v17(Database db) async {
    await db.execute('ALTER TABLE business_profile ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE customer_groups ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE customers ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE loans ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE repayment_schedule ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE payments ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE savings_accounts ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE savings_transactions ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE documents ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE holidays ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE audit_logs ADD COLUMN updated_at TEXT');
    await db.execute('ALTER TABLE settings ADD COLUMN updated_at TEXT');

    final now = syncTimestamp();
    await db.execute(
        'UPDATE business_profile SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE customer_groups SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE customers SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE loans SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE repayment_schedule SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE payments SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE savings_accounts SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE savings_transactions SET updated_at = ? WHERE updated_at IS NULL',
        [now]);
    await db.execute(
        'UPDATE documents SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE holidays SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE audit_logs SET updated_at = ? WHERE updated_at IS NULL', [now]);
    await db.execute(
        'UPDATE settings SET updated_at = ? WHERE updated_at IS NULL', [now]);

    await createSyncSchema(db);
  }

  /// Creates the cloud-sync bookkeeping tables and triggers. Safe to run on a
  /// fresh install (from [_onCreate]) and on upgrade (from [_v17]).
  static Future<void> createSyncSchema(Database db) async {
    await db.execute('''
      CREATE TABLE sync_flags (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_meta (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_pushed_at TEXT,
        last_pulled_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_tombstones (
        deleted_table TEXT NOT NULL,
        deleted_row_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        PRIMARY KEY (deleted_table, deleted_row_id)
      )
    ''');
    await db.insert('sync_meta', {'id': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);

    for (final table in _syncTables) {
      await createSyncTriggersForTable(db, table);
    }
  }

  /// Recreates the stamp/tombstone change-tracking triggers for a single
  /// tracked table. Idempotent: existing triggers for the table are dropped
  /// first. Used by [createSyncSchema] and by table-recreate migrations (v21)
  /// that rebuild a tracked table and would otherwise silently lose its
  /// triggers (SQLite drops a table's triggers when the table is dropped).
  static Future<void> createSyncTriggersForTable(
      Database db, String table) async {
    final pk = _syncTablePrimaryKeys[table]!;
    const guard =
        "COALESCE((SELECT value FROM sync_flags WHERE key = 'pull_in_progress'), '0') = '0'";
    final stamp = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";
    final names = ['ins', 'upd', 'del'];
    for (final name in names) {
      await db.execute('DROP TRIGGER IF EXISTS trg_${table}_$name');
    }
    // Stamp on INSERT / UPDATE unless a pull is in progress (the sync
    // service sets sync_flags.pull_in_progress = '1' while it writes rows
    // fetched from the cloud, so pulled rows keep the remote timestamp).
    final ins = 'CREATE TRIGGER trg_${table}_ins AFTER INSERT ON $table '
        'WHEN $guard '
        'BEGIN UPDATE $table SET updated_at = $stamp WHERE $pk = NEW.$pk; END';
    final upd = 'CREATE TRIGGER trg_${table}_upd AFTER UPDATE ON $table '
        'WHEN $guard '
        'BEGIN UPDATE $table SET updated_at = $stamp WHERE $pk = NEW.$pk; END';
    // Record a tombstone so the cloud delete can be replicated to other
    // devices (cascaded deletes are captured too, since SQLite fires the
    // DELETE trigger for each row a CASCADE removes).
    final del = 'CREATE TRIGGER trg_${table}_del AFTER DELETE ON $table '
        'WHEN $guard '
        "BEGIN INSERT INTO sync_tombstones (deleted_table, deleted_row_id, deleted_at) "
        "VALUES ('$table', OLD.$pk, $stamp); END";
    await db.execute(ins);
    await db.execute(upd);
    await db.execute(del);
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
