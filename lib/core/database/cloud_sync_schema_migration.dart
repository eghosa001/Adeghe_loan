import 'package:sqflite_sqlcipher/sqflite.dart';

/// Installs the durable local state required by server-versioned cloud sync.
/// Kept separate from the historical v1-v24 migrations so the sync protocol
/// can evolve without rewriting old migration history.
class CloudSyncSchemaMigration {
  CloudSyncSchemaMigration._();

  static const _tables = <String>[
    'business_profile', 'customer_groups', 'customers', 'loans', 'payments',
    'savings_accounts', 'savings_transactions', 'documents', 'holidays',
  ];

  static const _primaryKeys = <String, String>{
    'business_profile': 'id', 'customer_groups': 'id', 'customers': 'id',
    'loans': 'id', 'payments': 'id', 'savings_accounts': 'id',
    'savings_transactions': 'id', 'documents': 'id', 'holidays': 'id',
  };

  static Future<void> install(Database db) async {
    for (final table in _tables) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == 'sync_version')) {
        await db.execute('ALTER TABLE $table ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
      }
      if (!columns.any((c) => c['name'] == 'sync_dirty')) {
        await db.execute('ALTER TABLE $table ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_version ON $table(sync_version)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_dirty ON $table(sync_dirty)');
      await _installDeleteTrigger(db, table, _primaryKeys[table]!);
      await _installDirtyTriggers(db, table, _primaryKeys[table]!);
    }

    final tombstoneColumns = await db.rawQuery('PRAGMA table_info(sync_tombstones)');
    if (!tombstoneColumns.any((c) => c['name'] == 'sync_version')) {
      await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
    }
    if (!tombstoneColumns.any((c) => c['name'] == 'sync_dirty')) {
      await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_tombstones_sync_version ON sync_tombstones(sync_version)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_tombstones_sync_dirty ON sync_tombstones(sync_dirty)');

    final metaColumns = await db.rawQuery('PRAGMA table_info(sync_meta)');
    if (!metaColumns.any((c) => c['name'] == 'last_pulled_version')) {
      await db.execute('ALTER TABLE sync_meta ADD COLUMN last_pulled_version INTEGER NOT NULL DEFAULT 0');
    }
    await _installEntityIntegrityTriggers(db);
  }

  static Future<void> _installDirtyTriggers(Database db, String table, String pk) async {
    final insertName = 'trg_v25_${table}_dirty_insert';
    final updateName = 'trg_v25_${table}_dirty_update';
    await db.execute('DROP TRIGGER IF EXISTS $insertName');
    await db.execute('DROP TRIGGER IF EXISTS $updateName');
    const guard = "COALESCE((SELECT value FROM sync_flags WHERE key = 'pull_in_progress'), '0') != '1'";
    await db.execute('''
      CREATE TRIGGER $insertName AFTER INSERT ON $table
      WHEN $guard AND NEW.sync_dirty = 0
      BEGIN UPDATE $table SET sync_dirty = 1 WHERE $pk = NEW.$pk; END
    ''');
    await db.execute('''
      CREATE TRIGGER $updateName AFTER UPDATE ON $table
      WHEN $guard AND NEW.sync_dirty = 0
      BEGIN UPDATE $table SET sync_dirty = 1 WHERE $pk = NEW.$pk; END
    ''');
  }

  static Future<void> _installDeleteTrigger(Database db, String table, String pk) async {
    final name = 'trg_v25_${table}_delete';
    await db.execute('DROP TRIGGER IF EXISTS $name');
    const guard = "COALESCE((SELECT value FROM sync_flags WHERE key = 'pull_in_progress'), '0') != '1'";
    await db.execute('''
      CREATE TRIGGER $name AFTER DELETE ON $table
      WHEN $guard
      BEGIN
        INSERT OR REPLACE INTO sync_tombstones
          (deleted_table, deleted_row_id, deleted_at, sync_version, sync_dirty)
        VALUES ('$table', OLD.$pk, COALESCE(OLD.updated_at, strftime('%Y-%m-%dT%H:%M:%fZ','now')),
          COALESCE(OLD.sync_version, 0), 1);
      END
    ''');
  }

  /// Enforces relationships that ordinary SQLite foreign keys cannot express.
  /// A payment must use the same customer as its loan; a document linked to a
  /// loan must likewise belong to that loan's customer. This protects imports,
  /// restores, and every repository path, not just normal UI writes.
  static Future<void> _installEntityIntegrityTriggers(Database db) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_v25_payments_customer_match');
    await db.execute('''
      CREATE TRIGGER trg_v25_payments_customer_match
      BEFORE INSERT ON payments
      BEGIN
        SELECT RAISE(ABORT, 'payment customer does not match loan customer')
        WHERE NOT EXISTS (SELECT 1 FROM loans l
          WHERE l.id = NEW.loan_id AND l.customer_id = NEW.customer_id);
      END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_v25_payments_customer_match_update');
    await db.execute('''
      CREATE TRIGGER trg_v25_payments_customer_match_update
      BEFORE UPDATE OF loan_id, customer_id ON payments
      BEGIN
        SELECT RAISE(ABORT, 'payment customer does not match loan customer')
        WHERE NOT EXISTS (SELECT 1 FROM loans l
          WHERE l.id = NEW.loan_id AND l.customer_id = NEW.customer_id);
      END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_v25_documents_customer_match');
    await db.execute('''
      CREATE TRIGGER trg_v25_documents_customer_match
      BEFORE INSERT ON documents
      WHEN NEW.loan_id IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'document customer does not match loan customer')
        WHERE NOT EXISTS (SELECT 1 FROM loans l
          WHERE l.id = NEW.loan_id AND l.customer_id = NEW.customer_id);
      END
    ''');
    await db.execute('DROP TRIGGER IF EXISTS trg_v25_documents_customer_match_update');
    await db.execute('''
      CREATE TRIGGER trg_v25_documents_customer_match_update
      BEFORE UPDATE OF loan_id, customer_id ON documents
      WHEN NEW.loan_id IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'document customer does not match loan customer')
        WHERE NOT EXISTS (SELECT 1 FROM loans l
          WHERE l.id = NEW.loan_id AND l.customer_id = NEW.customer_id);
      END
    ''');
  }
}
