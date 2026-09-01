import 'dart:async';
import 'dart:io' show Platform, File;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit, DatabaseException;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/app_constants.dart';
import '../security/secure_storage_service.dart';
import 'migrations.dart';

class DatabaseService {
  static const int _databaseVersion = 24;
  final SecureStorageService _secureStorage;

  final Future<Database> Function()? _openOverride;

  DatabaseService(this._secureStorage) : _openOverride = null;

  @visibleForTesting
  DatabaseService.withOpenOverride(
    this._secureStorage,
    Future<Database> Function() open,
  ) : _openOverride = open;

  Future<Database>? _openFuture;
  Future<void>? _exclusiveGate;
  Future<void>? _exclusiveTail;
  String? _databasePath;

  Future<Database> get database {
    final gate = _exclusiveGate;
    if (gate != null) return gate.then((_) => _open());
    return _open();
  }

  Future<Database> _open() {
    final memo = _openFuture;
    if (memo != null) return memo;
    final open = _openOverride ?? _initDatabase;
    late final Future<Database> future;
    future = open().then<Database>(
      (db) => db,
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_openFuture, future)) _openFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _openFuture = future;
    return future;
  }

  Future<String> get databasePath async {
    if (_databasePath != null) return _databasePath!;
    final documentsDirectory = await getApplicationDocumentsDirectory();
    _databasePath = join(documentsDirectory.path, AppConstants.databaseName);
    return _databasePath!;
  }

  Future<void> close() async {
    final current = _openFuture;
    _openFuture = null;
    if (current != null) {
      try {
        final db = await current;
        await db.close();
      } catch (_) {}
    }
  }

  Future<T> withExclusiveAccess<T>(Future<T> Function() action) async {
    final previous = _exclusiveTail;
    final done = Completer<void>();
    _exclusiveTail = done.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    final gate = Completer<void>();
    _exclusiveGate = gate.future;
    Object? actionError;
    try {
      await close();
      return await action();
    } catch (error) {
      actionError = error;
      rethrow;
    } finally {
      _exclusiveGate = null;
      try {
        await database;
      } catch (reopenError) {
        if (actionError == null) {
          Error.throwWithStackTrace(reopenError, StackTrace.current);
        }
      } finally {
        if (!gate.isCompleted) gate.complete();
        if (!done.isCompleted) done.complete();
      }
    }
  }

  Future<bool> verifyDatabaseFile(String path) async {
    final encryptionKey = await _secureStorage.getDatabaseKey();
    Database? db;
    try {
      if (Platform.isWindows) {
        db = await _openWindowsDatabaseRaw(path, encryptionKey, readOnly: true);
      } else {
        db = await openDatabase(path, password: encryptionKey, readOnly: true);
      }
      final version = await db.getVersion();
      return version >= 1 && version <= _databaseVersion;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, AppConstants.databaseName);
    final encryptionKey = await _secureStorage.getDatabaseKey();

    if (Platform.isWindows) return _openWindowsDatabase(path, encryptionKey);

    return openDatabase(
      path,
      password: encryptionKey,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: _onConfigure,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<Database> _openWindowsDatabase(
    String path,
    String encryptionKey,
  ) async {
    sqfliteFfiInit();
    try {
      return await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onConfigure: (db) async {
            await db.execute(_cipherKeySql(encryptionKey));
            await _onConfigure(db);
          },
          onUpgrade: _onUpgrade,
          onOpen: _onOpen,
        ),
      );
    } on DatabaseException catch (e) {
      final message = e.toString();
      if (message.contains('SqliteException(26)') ||
          message.contains('file is not a database')) {
        final file = File(path);
        var recoveryPath = path;
        if (await file.exists()) {
          final stamp = DateTime.now()
              .toUtc()
              .toIso8601String()
              .replaceAll(':', '-');
          final recovery = File('$path.recovery-$stamp');
          try {
            await file.copy(recovery.path);
            recoveryPath = recovery.path;
          } catch (_) {
            // The original file is intentionally left untouched.
          }
        }
        throw DatabaseRecoveryException(
          'The database could not be opened safely. No data was deleted. '
          'Recovery copy: $recoveryPath',
          recoveryPath,
        );
      }
      rethrow;
    }
  }

  Future<Database> _openWindowsDatabaseRaw(
    String path,
    String encryptionKey, {
    bool readOnly = false,
  }) async {
    sqfliteFfiInit();
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: readOnly,
        onConfigure: (db) async {
          await db.execute(_cipherKeySql(encryptionKey));
        },
      ),
    );
  }

  static String _cipherKeySql(String encryptionKey) {
    final escaped = encryptionKey.replaceAll("'", "''");
    return "PRAGMA key = '$escaped'";
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
  }

  Future<void> _onOpen(Database db) async {
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
        owner_name TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE customer_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
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
        updated_at TEXT,
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
        type TEXT DEFAULT 'partial',
        status TEXT NOT NULL DEFAULT 'completed',
        prior_loan_status TEXT,
        client_request_id TEXT,
        created_at TEXT,
        updated_at TEXT,
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
        updated_at TEXT,
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
        updated_at TEXT,
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
        is_enabled INTEGER NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        user TEXT NOT NULL,
        action TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        details TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE savings_accounts (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL UNIQUE,
        balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
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
        updated_at TEXT,
        FOREIGN KEY (savings_account_id) REFERENCES savings_accounts(id) ON DELETE CASCADE
      )
    ''');

    await _createIndexes(db);
    await DatabaseMigrations.createSyncSchema(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DatabaseMigrations.run(db, oldVersion, newVersion);
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(full_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_unique ON customers(phone) WHERE status != 'archived'",
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_nin_unique ON customers(nin) WHERE status != 'archived'",
    );
    await db.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_bvn_unique ON customers(bvn) WHERE status != 'archived'",
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customers_group ON customers(group_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loans_customer ON loans(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_loan ON payments(loan_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_customer ON documents(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan ON repayment_schedule(loan_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_customer_groups_name ON customer_groups(name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_savings_accounts_customer ON savings_accounts(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_savings_transactions_account ON savings_transactions(savings_account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_loan_date ON payments(loan_id, payment_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repayment_schedule_loan_date ON repayment_schedule(loan_id, due_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loans_type_status ON loans(loan_type, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loans_type_date ON loans(loan_type, loan_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_savings_txns_ref_payment ON savings_transactions(reference_loan_payment_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_customer ON payments(customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(payment_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_savings_txns_created ON savings_transactions(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_holidays_date ON holidays(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_documents_loan ON documents(loan_id)',
    );
  }
}

/// Signals that opening the financial database failed and automatic recovery
/// is required. The existing database file is never deleted automatically.
class DatabaseRecoveryException implements Exception {
  const DatabaseRecoveryException(this.message, this.recoveryPath);

  final String message;
  final String recoveryPath;

  @override
  String toString() => message;
}
