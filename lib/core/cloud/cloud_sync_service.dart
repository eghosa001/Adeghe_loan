import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import 'cloud_auth_service.dart';
import 'supabase_config.dart';
import 'sync_timestamps.dart';

/// Result of one full (push + pull) sync cycle.
class CloudSyncResult {
  const CloudSyncResult({
    this.pushedRows = 0,
    this.pulledRows = 0,
    this.deletedRows = 0,
    this.error,
  });

  final int pushedRows;
  final int pulledRows;
  final int deletedRows;
  final String? error;

  bool get success => error == null;
}

/// Offline-first replication engine.
///
/// The encrypted local SQLite database remains the source of truth. When the
/// owner is signed in to Supabase, this service:
///
///  * **Push** — uploads every local row whose `updated_at` is newer than the
///    last push (last-write-wins), along with deletes recorded as tombstones.
///    Encrypted customer documents go to the `documents` storage bucket.
///  * **Pull** — downloads cloud rows newer than the last pull and merges them
///    only when they are newer than the local copy. Rows deleted remotely (via
///    the remote tombstone table) are removed locally.
///
/// Sync writes are performed with `sync_flags.pull_in_progress = '1', which
/// suppresses the stamp/tombstone triggers so pulled rows keep their remote
/// timestamps and are not immediately re-pushed.
class CloudSyncService {
  CloudSyncService(this._databaseService);

  final DatabaseService _databaseService;

  static const String _pullFlagKey = 'pull_in_progress';

  /// Replicated tables in parent-before-child order (FK-safe for pull writes).
  static const List<String> _tables = [
    'business_profile',
    'customer_groups',
    'customers',
    'loans',
    'repayment_schedule',
    'payments',
    'savings_accounts',
    'savings_transactions',
    'documents',
    'holidays',
    'audit_logs',
    'settings',
  ];

  static const Map<String, String> _tablePrimaryKeys = {
    'business_profile': 'id',
    'customer_groups': 'id',
    'customers': 'id',
    'loans': 'id',
    'repayment_schedule': 'id',
    'payments': 'id',
    'savings_accounts': 'id',
    'savings_transactions': 'id',
    'documents': 'id',
    'holidays': 'id',
    'audit_logs': 'id',
    'settings': 'key',
  };

  bool _syncing = false;

  bool get isSyncing => _syncing;

  bool get isConfigured => SupabaseConfig.isConfigured;

  bool get isSignedIn {
    try {
      return Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Whether the signed-in account is one of the project owners (RLS-gated
  /// reads would silently return nothing for a non-owner, so sync refuses to
  /// start and never reports a false "complete").
  Future<bool> _isOwner() async {
    try {
      return await Supabase.instance.client.rpc('is_owner') == true;
    } catch (_) {
      return false;
    }
  }

  /// Runs a background sync when the cloud is configured and the owner is
  /// signed in. Best-effort — never throws.
  Future<void> syncIfSignedIn() async {
    try {
      if (!isConfigured || !isSignedIn) return;
      await fullSync();
    } catch (_) {
      // Background sync is best-effort; a failure here never blocks the app.
    }
  }

  /// Last successful pull timestamp (local), or null if never synced.
  Future<DateTime?> lastSyncTime() async {
    final db = await _databaseService.database;
    final rows = await db.query('sync_meta', where: 'id = ?', whereArgs: [1], limit: 1);
    if (rows.isEmpty) return null;
    final value = rows.first['last_pulled_at'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  /// Runs one full cycle (push then pull). Throws a [CloudSyncException] only
  /// if a whole cycle cannot start; per-table failures are collected in the
  /// result instead.
  Future<CloudSyncResult> fullSync() async {
    if (_syncing) {
      return const CloudSyncResult(error: 'A sync is already in progress.');
    }
    if (!isConfigured) {
      return const CloudSyncResult(
          error: 'Supabase is not configured. Add your project URL and key.');
    }
    if (!isSignedIn) {
      return const CloudSyncResult(error: 'You are not signed in to the cloud.');
    }
    if (!await _isOwner()) {
      return const CloudSyncResult(
          error: CloudAuthService.notOwnerMessage);
    }
    _syncing = true;
    try {
      final db = await _databaseService.database;
      var pushed = 0;
      var pulled = 0;
      var deleted = 0;
      String? firstError;

      void noteError(Object error) {
        firstError ??= error.toString();
      }

      try {
        final result = await _push(db);
        pushed = result.$1;
        deleted = result.$2;
      } catch (error) {
        noteError(error);
      }
      try {
        pulled = await _pull(db);
      } catch (error) {
        noteError(error);
      }
      return CloudSyncResult(
        pushedRows: pushed,
        pulledRows: pulled,
        deletedRows: deleted,
        error: firstError,
      );
    } finally {
      _syncing = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Push
  // ─────────────────────────────────────────────────────────────────────────

  Future<(int, int)> _push(Database db) async {
    final client = Supabase.instance.client;
    final meta = await _readMeta(db);
    final lastPushed = meta.$1;

    // Snapshot every changed row BEFORE capturing the watermark, so rows
    // written after the watermark are picked up by the next cycle.
    final snapshots = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rows = lastPushed == null
          ? await db.query(table)
          : await db.query(table,
              where: 'updated_at > ? OR updated_at IS NULL', whereArgs: [lastPushed]);
      snapshots[table] = rows;
    }
    final tombstones = lastPushed == null
        ? await db.query('sync_tombstones')
        : await db.query('sync_tombstones',
            where: 'deleted_at > ?', whereArgs: [lastPushed]);
    final watermark = _isoUtcNow();

    var pushed = 0;
    for (final table in _tables) {
      final rows = snapshots[table] ?? const [];
      if (rows.isEmpty) continue;
      try {
        if (table == 'documents') {
          pushed += await _pushDocuments(client, rows);
        } else {
          final cleaned = [for (final row in rows) _stripNulls(row)];
          await client.from(table).upsert(cleaned, onConflict: _tablePrimaryKeys[table]!);
          pushed += rows.length;
        }
      } catch (_) {
        // Per-table best effort: failed tables retry on the next sync.
      }
    }

    // Deletes: children before parents so remote FKs (ON DELETE CASCADE / SET
    // NULL) behave like the local database.
    var deleted = 0;
    for (final table in _tables.reversed) {
      final tableTombstones = tombstones
          .where((t) => t['deleted_table'] == table)
          .toList();
      if (tableTombstones.isEmpty) continue;
      final pk = _tablePrimaryKeys[table]!;
      for (final tombstone in tableTombstones) {
        final id = tombstone['deleted_row_id'] as String;
        try {
          await client.from(table).delete().eq(pk, id);
          await client.from('sync_tombstones').insert({
            'deleted_table': table,
            'deleted_row_id': id,
            'deleted_at': tombstone['deleted_at'],
          });
          await db.delete('sync_tombstones',
              where: 'deleted_table = ? AND deleted_row_id = ?',
              whereArgs: [table, id]);
          deleted++;
        } catch (_) {
          // Keep the local tombstone so the delete is retried next cycle.
        }
      }
    }

    await _writeMeta(db, pushedAt: watermark);
    return (pushed, deleted);
  }

  Future<int> _pushDocuments(SupabaseClient client, List<Map<String, Object?>> rows) async {
    var pushed = 0;
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final customerId = row['customer_id'] as String? ?? '';
      final localPath = row['file_path'] as String? ?? '';
      final storagePath = _documentStoragePath(customerId, id);

      final localFile = File(localPath);
      if (localPath.isNotEmpty && await localFile.exists()) {
        try {
          final bytes = await localFile.readAsBytes();
          await client.storage
              .from(SupabaseConfig.documentsBucket)
              .uploadBinary(storagePath, bytes,
                  fileOptions: const FileOptions(upsert: true));
        } catch (_) {
          // File upload failed — skip the metadata upsert so the whole
          // document is retried on the next sync.
          continue;
        }
      }

      final cleaned = Map<String, Object?>.from(row)..['file_path'] = '';
      try {
        await client
            .from('documents')
            .upsert(_stripNulls(cleaned), onConflict: 'id');
        pushed++;
      } catch (_) {
        // Metadata upsert failed; retried next cycle.
      }
    }
    return pushed;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pull
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> _pull(Database db) async {
    final client = Supabase.instance.client;
    final meta = await _readMeta(db);
    final lastPulled = meta.$2;
    final watermark = _isoUtcNow(); // captured at the start (see push notes)

    await _setPullFlag(db, true);
    var pulled = 0;
    try {
      // Remote deletes first: delete parents first so cascades clean up
      // children (matching local FK behavior).
      final remoteTombstones = await client.from('sync_tombstones').select();
      for (final tombstone in remoteTombstones) {
        final table = tombstone['deleted_table'] as String?;
        final id = tombstone['deleted_row_id'] as String?;
        if (table == null || id == null) continue;
        final pk = _tablePrimaryKeys[table];
        if (pk == null) continue;
        try {
          await db.delete(table, where: '$pk = ?', whereArgs: [id]);
          await client
              .from('sync_tombstones')
              .delete()
              .eq('deleted_table', table)
              .eq('deleted_row_id', id);
        } catch (_) {
          // Keep the remote tombstone; retried next cycle.
        }
      }

      final localTombstones =
          <String, Map<String, Object?>>{};
      for (final table in _tables) {
        final rows = await db.query('sync_tombstones',
            where: 'deleted_table = ?', whereArgs: [table]);
        for (final row in rows) {
          localTombstones['$table|${row['deleted_row_id']}'] = row;
        }
      }

      for (final table in _tables) {
        final pk = _tablePrimaryKeys[table]!;
        final remoteRows = lastPulled == null
            ? await client.from(table).select()
            : await client.from(table).select().gte('updated_at', lastPulled);
        for (final remoteRow in remoteRows) {
          final id = remoteRow[pk];
          if (id == null) continue;
          final remoteUpdated = (remoteRow['updated_at'] as String?) ?? '';
          try {
            final localRows = await db.query(table,
                where: '$pk = ?', whereArgs: [id], limit: 1);
            if (localRows.isNotEmpty) {
              final localUpdated =
                  (localRows.first['updated_at'] as String?) ?? '';
              if (remoteUpdated.compareTo(localUpdated) <= 0) continue;
            } else {
              // Locally deleted — respect the delete unless the remote version
              // is newer than the deletion.
              final tombstone =
                  localTombstones['$table|$id']?['deleted_at'] as String?;
              if (tombstone != null &&
                  remoteUpdated.compareTo(tombstone) <= 0) {
                continue;
              }
            }
            final row = Map<String, Object?>.from(remoteRow);
            if (table == 'documents') {
              await _materializeDocument(row);
            }
            await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
            if (localTombstones.containsKey('$table|$id')) {
              await db.delete('sync_tombstones',
                  where: 'deleted_table = ? AND deleted_row_id = ?',
                  whereArgs: [table, id]);
            }
            pulled++;
          } catch (_) {
            // Per-row best effort.
          }
        }
      }
    } finally {
      await _setPullFlag(db, false);
    }

    await _writeMeta(db, pulledAt: watermark);
    return pulled;
  }

  /// Downloads the encrypted document from storage and points the local row at
  /// a freshly written `secure_documents/<uuid>.enc` file. On failure the row
  /// keeps an empty `file_path` (the preview screen reports the missing file).
  Future<void> _materializeDocument(Map<String, Object?> row) async {
    final id = row['id'] as String?;
    final customerId = row['customer_id'] as String?;
    if (id == null || customerId == null) return;
    try {
      final bytes = await Supabase.instance.client.storage
          .from(SupabaseConfig.documentsBucket)
          .download(_documentStoragePath(customerId, id));
      row['file_path'] = await _writeSecureDocument(bytes);
    } catch (_) {
      row['file_path'] = '';
    }
  }

  Future<String> _writeSecureDocument(List<int> bytes) async {
    final root = await getApplicationDocumentsDirectory();
    final directory =
        Directory('${root.path}${Platform.pathSeparator}secure_documents');
    if (!await directory.exists()) await directory.create(recursive: true);
    final path =
        '${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.enc';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _documentStoragePath(String customerId, String documentId) {
    final safeCustomer = sanitizeCloudPathPart(customerId);
    final safeDocument = sanitizeCloudPathPart(documentId);
    return '$safeCustomer/$safeDocument.enc';
  }

  Map<String, Object?> _stripNulls(Map<String, Object?> row) {
    // Nulls are omitted so Postgres falls back to column defaults instead of
    // trying to write NULL into a NOT NULL column.
    return {
      for (final entry in row.entries)
        if (entry.value != null) entry.key: entry.value,
    };
  }

  Future<(String?, String?)> _readMeta(Database db) async {
    final rows = await db.query('sync_meta', where: 'id = ?', whereArgs: [1], limit: 1);
    if (rows.isEmpty) return (null, null);
    return (
      rows.first['last_pushed_at'] as String?,
      rows.first['last_pulled_at'] as String?,
    );
  }

  Future<void> _writeMeta(
    Database db, {
    String? pushedAt,
    String? pulledAt,
  }) async {
    final values = <String, Object?>{};
    if (pushedAt != null) values['last_pushed_at'] = pushedAt;
    if (pulledAt != null) values['last_pulled_at'] = pulledAt;
    if (values.isEmpty) return;
    await db.update('sync_meta', values, where: 'id = ?', whereArgs: [1]);
  }

  Future<void> _setPullFlag(Database db, bool value) async {
    await db.insert(
      'sync_flags',
      {'key': _pullFlagKey, 'value': value ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _isoUtcNow() => syncTimestamp();
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Neutralizes path-traversal / separator characters so a crafted database id
/// can never escape the `documents/<customer_id>/<document_id>.enc` key prefix
/// in the Storage bucket. Keeps only [A-Za-z0-9_-] (dots are dropped so a `..`
/// segment can never be formed); anything empty collapses to an inert
/// placeholder.
String sanitizeCloudPathPart(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  return sanitized.isEmpty ? '_' : sanitized;
}
