import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
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
    this.mergedCustomers = 0,
    this.error,
  });

  final int pushedRows;
  final int pulledRows;
  final int deletedRows;
  final int mergedCustomers;
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

  /// Called after every completed pull (best-effort; failures are swallowed).
  /// `fullSync` uses it to re-derive repayment schedules from the freshly
  /// synced source data — the derived `repayment_schedule` rows themselves are
  /// never replicated (see `_tables`), so each device recomputes them locally.
  Future<void> Function()? onPullComplete;

  static const String _pullFlagKey = 'pull_in_progress';

  /// Remote tombstones applied per pull cycle. Bounds how much deletion a
  /// single (possibly hostile or corrupted) remote tombstone batch can force
  /// on this device; any surplus is applied on later cycles.
  static const int _maxRemoteTombstonesPerCycle = 500;

  /// Minimum time between automatically triggered background syncs. Rapid
  /// lock/unlock cycles would otherwise each kick off a full push+pull and can
  /// hit Supabase request/concurrency limits. Manual "Sync now" is unaffected.
  /// Two minutes keeps loan history (payments + the schedules derived from
  /// them) visible on the other device within a couple of minutes of a change
  /// while staying well inside Supabase request/concurrency limits (two owners,
  /// ~30 cycles/hr worst case).
  static const Duration _minAutoSyncInterval = Duration(minutes: 2);

  DateTime? _lastAutoSyncAt;

  /// Replicated tables in parent-before-child order (FK-safe for pull writes).
  /// NOTE: `repayment_schedule` is intentionally NOT here — it is a derived
  /// cache recomputed on each device from the synced source data (loans +
  /// payments + savings + holidays) after every pull.
  static const List<String> _tables = [
    'business_profile',
    'customer_groups',
    'customers',
    'loans',
    'payments',
    'savings_accounts',
    'savings_transactions',
    'documents',
    'holidays',
  ];

  static const Map<String, String> _tablePrimaryKeys = {
    'business_profile': 'id',
    'customer_groups': 'id',
    'customers': 'id',
    'loans': 'id',
    'payments': 'id',
    'savings_accounts': 'id',
    'savings_transactions': 'id',
    'documents': 'id',
    'holidays': 'id',
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
  /// signed in. Best-effort — never throws. Throttled to one automatic attempt
  /// every [_minAutoSyncInterval] so rapid lock/unlock cycles cannot hammer
  /// the cloud.
  Future<void> syncIfSignedIn() async {
    try {
      if (!isConfigured || !isSignedIn) return;
      final now = DateTime.now();
      final last = _lastAutoSyncAt;
      if (last != null && now.difference(last) < _minAutoSyncInterval) {
        return;
      }
      _lastAutoSyncAt = now;
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

      var attempted = 0;
      var pushFailures = 0;
      var mergedCustomers = 0;
      var failedTables = <String>{};
      try {
        final result = await _push(db);
        pushed = result.pushed;
        deleted = result.deleted;
        attempted = result.attempted;
        pushFailures = result.failures;
        mergedCustomers = result.merged;
        failedTables = result.failedTables;
      } catch (error) {
        noteError(error);
      }
      var pullFailures = 0;
      try {
        final result = await _pull(db);
        pulled = result.pulled;
        pullFailures = result.failures;
      } catch (error) {
        noteError(error);
      }

      // After every pull, re-derive all repayment schedules from the freshly
      // synced source data (loans + payments + savings + holidays). The derived
      // schedule rows are never replicated, so each device must recompute them
      // locally. Best-effort: a rebuild failure must not fail the sync cycle.
      try {
        await onPullComplete?.call();
      } catch (_) {}

      // Never report a false "Sync complete": any per-table/per-row failure —
      // or a cycle that moved nothing despite local changes to push — surfaces
      // as an error so the user can investigate (RLS, network, owner access).
      String? error = firstError;
      if (error == null && (pushFailures > 0 || pullFailures > 0)) {
        final failedList = failedTables.toList()..sort();
        final failedDetails =
            failedList.isEmpty ? '' : ' Tables: ${failedList.join(', ')}.';
        error = 'Sync finished but $pushFailures push and $pullFailures pull '
            'item(s) failed and were not replicated. They retry on the next '
            'sync.$failedDetails';
      } else if (error == null &&
          attempted > 0 &&
          pushed == 0 &&
          pulled == 0 &&
          deleted == 0) {
        error = 'Nothing was replicated (0 of $attempted local changes reached '
            'the cloud). Check the owner access and network, then try again.';
      }
      return CloudSyncResult(
        pushedRows: pushed,
        pulledRows: pulled,
        deletedRows: deleted,
        mergedCustomers: mergedCustomers,
        error: error,
      );
    } finally {
      _syncing = false;
    }
  }

  /// Resets the local push watermark so the next sync re-uploads EVERY local
  /// row (a full push), then runs one full cycle.
  ///
  /// Incremental push only ever sends rows newer than `last_pushed_at`, so if
  /// the cloud is ever wiped or recreated, the older (unmodified) local rows
  /// would be skipped forever and any child rows referencing them would fail
  /// their foreign keys. Calling this once forces a complete re-upload that
  /// repopulates the cloud from this device. It intentionally overwrites the
  /// cloud with THIS device's data — only use it to recover from a cloud
  /// reset, never as routine sync.
  Future<CloudSyncResult> forceFullReupload() async {
    final db = await _databaseService.database;
    await db.update('sync_meta', {'last_pushed_at': null},
        where: 'id = ?', whereArgs: [1]);
    return fullSync();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Push
  // ─────────────────────────────────────────────────────────────────────────

  Future<
      ({
        int pushed,
        int deleted,
        int attempted,
        int failures,
        int merged,
        Set<String> failedTables,
      })> _push(Database db) async {
    final client = Supabase.instance.client;
    final meta = await _readMeta(db);
    final lastPushed = meta.$1;

    // Merge locally-duplicated customers (same phone, non-archived) BEFORE
    // snapshotting, so the surviving record, the re-pointed children, and the
    // tombstone for each removed duplicate all reach the cloud in this cycle —
    // instead of the cloud (and the other device) inheriting the duplicates.
    final merged = await _resolveDuplicateCustomers(db);

    // Snapshot every changed row BEFORE capturing the watermark, so rows
    // written after the watermark are picked up by the next cycle.
    final snapshots = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rows = lastPushed == null
          ? await db.query(table)
          : await db.query(table,
              where: 'updated_at > ? OR updated_at IS NULL',
              whereArgs: [lastPushed]);
      snapshots[table] = rows;
    }
    final tombstones = lastPushed == null
        ? await db.query('sync_tombstones')
        : await db.query('sync_tombstones',
            where: 'deleted_at > ?', whereArgs: [lastPushed]);
    final watermark = _isoUtcNow();

    var pushed = 0;
    var attempted = tombstones.length;
    var failures = 0;
    final failedTables = <String>{};
    for (final table in _tables) {
      final rows = snapshots[table] ?? const [];
      if (rows.isEmpty) continue;
      attempted += rows.length;
      try {
        if (table == 'documents') {
          final documents = await _pushDocuments(client, rows);
          pushed += documents.pushed;
          failures += documents.failures;
        } else {
          // Rows are pushed in full (explicit NULLs included) so field-clearing
          // writes like changeGroup(id, null) propagate; regulated identifiers
          // (bvn/nin) are stripped first (see cloudSensitiveColumns). Chunked
          // so a large table never sends one oversized request or reads the
          // whole snapshot into a single upsert payload.
          final cleanedRows = [
            for (final row in rows) stripSensitiveColumns(table, row),
          ];
          for (final batch in _chunk(cleanedRows, 500)) {
            await client
                .from(table)
                .upsert(batch, onConflict: _tablePrimaryKeys[table]!);
          }
          pushed += rows.length;
        }
      } catch (_) {
        failures++;
        failedTables.add(table);
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
          failures++;
          failedTables.add(table);
        }
      }
    }

    // Only advance the push watermark when every table (and tombstone) pushed,
    // so a failed table is re-picked and retried next cycle instead of being
    // silently skipped forever. Successful upserts are idempotent.
    if (failedTables.isEmpty) {
      await _writeMeta(db, pushedAt: watermark);
    }
    return (
      pushed: pushed,
      deleted: deleted,
      attempted: attempted,
      failures: failures,
      merged: merged,
      failedTables: failedTables,
    );
  }

  /// Finds customers duplicated locally (same trimmed `phone`, both
  /// non-archived) and merges each duplicate into the canonical record. The
  /// canonical record is the earliest `date_registered` (ties broken by `id`)
  /// — a decision based purely on replicated data, so every device resolves
  /// the SAME survivor and the merge converges instead of fighting.
  ///
  /// Runs at the start of every push so duplicates (whether created locally or
  /// pulled from a second device) are resolved BEFORE the snapshot: the
  /// survivor's `updated_at`, the re-pointed child rows, and the tombstone for
  /// each removed duplicate are all captured by the same cycle and reach the
  /// cloud together. Returns the number of duplicate rows removed.
  Future<int> _resolveDuplicateCustomers(Database db) async {
    final rows = await db.query('customers', where: "status != 'archived'");
    final byPhone = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final phone = (row['phone'] as String?)?.trim();
      if (phone == null || phone.isEmpty) continue;
      byPhone.putIfAbsent(phone, () => []).add(row);
    }
    var merged = 0;
    for (final group in byPhone.values) {
      if (group.length < 2) continue;
      sortDuplicateCustomersByCanonicalOrder(group);
      final survivor = group.first;
      for (final duplicate in group.skip(1)) {
        await mergeDuplicateCustomerInto(db, duplicate, survivor);
        merged++;
      }
    }
    return merged;
  }

  Future<({int pushed, int failures})> _pushDocuments(
      SupabaseClient client, List<Map<String, Object?>> rows) async {
    var pushed = 0;
    var failures = 0;
    for (final row in rows) {
      final id = row['id'] as String?;
      if (id == null) {
        failures++;
        continue;
      }
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
          failures++;
          continue;
        }
      }

      final cleaned = Map<String, Object?>.from(row)..['file_path'] = '';
      try {
        await client
            .from('documents')
            .upsert(stripSensitiveColumns('documents', cleaned),
                onConflict: 'id');
        pushed++;
      } catch (_) {
        // Metadata upsert failed; counted as a failure and retried next cycle.
        failures++;
      }
    }
    return (pushed: pushed, failures: failures);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pull
  // ─────────────────────────────────────────────────────────────────────────

  Future<({int pulled, int failures})> _pull(Database db) async {
    final client = Supabase.instance.client;
    final meta = await _readMeta(db);
    final lastPulled = meta.$2;
    final watermark = _isoUtcNow(); // captured at the start (see push notes)

    await _setPullFlag(db, true);
    var pulled = 0;
    var failures = 0;
    try {
      // Remote deletes first: delete parents first so cascades clean up
      // children (matching local FK behavior). Each tombstone is validated so
      // a crafted or hostile row cannot mass-delete local data.
      final remoteTombstones =
          await _fetchAll(client.from('sync_tombstones').select());
      var appliedTombstones = 0;
      for (final tombstone in remoteTombstones) {
        if (appliedTombstones >= _maxRemoteTombstonesPerCycle) break;
        final table = tombstone['deleted_table'] as String?;
        final id = tombstone['deleted_row_id'] as String?;
        if (table == null || id == null) continue;
        if (!_isValidTombstone(table, id, tombstone['deleted_at'])) continue;
        final pk = _tablePrimaryKeys[table]!;
        try {
          await db.delete(table, where: '$pk = ?', whereArgs: [id]);
          await client
              .from('sync_tombstones')
              .delete()
              .eq('deleted_table', table)
              .eq('deleted_row_id', id);
          appliedTombstones++;
        } catch (_) {
          // Keep the remote tombstone; retried next cycle.
          failures++;
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
        final query = client.from(table).select();
        final filtered =
            lastPulled == null ? query : query.gte('updated_at', lastPulled);
        final remoteRows = await _fetchAll(filtered);
        if (remoteRows.isEmpty) continue;
        final sensitive = cloudSensitiveColumns[table];

        // Load the local copy of every remote id ONCE so the LWW merge is not
        // an N+1 `db.query` per remote row.
        final localRows = <String, Map<String, Object?>>{};
        final ids = remoteRows
            .map((r) => r[pk])
            .whereType<String>()
            .toSet()
            .toList();
        for (final idChunk in _chunk(ids, 400)) {
          final placeholders = List.filled(idChunk.length, '?').join(',');
          final chunkRows = await db.query(table,
              where: '$pk IN ($placeholders)', whereArgs: idChunk);
          for (final row in chunkRows) {
            final id = row[pk] as String;
            localRows[id] = row;
          }
        }

        for (final remoteRow in remoteRows) {
          final id = remoteRow[pk];
          if (id == null) continue;
          if (!isSaneCloudRow(table, remoteRow, pk)) {
            // API-3/API-4: a malformed, future-dated, or wrongly-typed row is
            // never applied — it would poison the LWW merge or crash strict
            // entity casts later. Counted as a failure so a partial pull is
            // never reported as a clean "Sync complete".
            failures++;
            continue;
          }
          final remoteUpdated = (remoteRow['updated_at'] as String?) ?? '';
          try {
            final localRow = localRows[id];
            if (localRow != null) {
              final localUpdated =
                  (localRow['updated_at'] as String?) ?? '';
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
            var row = Map<String, Object?>.from(remoteRow);
            if (sensitive != null && localRow != null) {
              // Regulated identifiers never leave this device: the cloud row
              // has no bvn/nin columns, so carry the local values across the
              // OR-REPLACE (which would otherwise reset them to NULL).
              for (final column in sensitive) {
                row[column] = localRow[column];
              }
            }
            if (table == 'customers') {
              // Names are stored ALL CAPS locally (owner decision); a remote
              // device running an older build may push mixed-case names, so
              // normalize the pulled row before it lands in the local DB.
              for (final column in const [
                'full_name',
                'next_of_kin',
                'guarantor_1_name',
                'guarantor_2_name',
              ]) {
                final value = row[column];
                if (value is String) {
                  row[column] = value.trim().toUpperCase();
                }
              }
            }
            if (table == 'documents') {
              await _materializeDocument(row);
            }
            await db.insert(table, row,
                conflictAlgorithm: ConflictAlgorithm.replace);
            if (localTombstones.containsKey('$table|$id')) {
              await db.delete('sync_tombstones',
                  where: 'deleted_table = ? AND deleted_row_id = ?',
                  whereArgs: [table, id]);
            }
            pulled++;
          } catch (_) {
            // Per-row best effort — counted as a failure so a partial pull is
            // never reported as a clean "Sync complete".
            failures++;
          }
        }
      }
    } finally {
      await _setPullFlag(db, false);
    }

    // Advance the pull watermark ONLY when every row applied. A failed row
    // (rejected by isSaneCloudRow, failed document materialization, or a DB
    // insert error) would otherwise be skipped forever: the next cycle pulls
    // updated_at >= lastPulled, and a failed row's timestamp is older than the
    // watermark captured here. Leaving the watermark put makes the next cycle
    // re-fetch (and re-apply, idempotently) everything since the last good
    // pull. This mirrors the push side's all-or-nothing watermark advance.
    if (failures == 0) {
      await _writeMeta(db, pulledAt: watermark);
    }
    return (pulled: pulled, failures: failures);
  }

  /// Whether a remote tombstone row may be applied locally: the table must be
  /// known, the id must look sane, and `deleted_at` must be a well-formed
  /// (non-future) sync timestamp.
  bool _isValidTombstone(String? table, String? id, Object? deletedAt) {
    if (table == null || id == null) return false;
    if (_tablePrimaryKeys[table] == null) return false;
    if (id.isEmpty || id.length > 64) return false;
    return isValidSyncTimestamp(deletedAt as String?);
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

    // On Windows, attempt to restrict file ACLs to the current user so other
    // local users cannot read the secure document files. This is best-effort
    // and will be ignored on failure.
    if (Platform.isWindows) {
      try {
        final user = Platform.environment['USERNAME'] ?? '';
        if (user.isNotEmpty) {
          await Process.run('icacls', [path, '/inheritance:r', '/grant:r', '$user:R']);
        }
      } catch (_) {
        // Ignore failures; directory security is best-effort.
      }
    }

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

  /// Fetches every row a [PostgrestFilterBuilder] can produce, paging with
  /// `.range()`. PostgREST caps a single response at `max-rows` (default
  /// 1000), so an unpaginated `select()` would silently drop rows on any table
  /// with more than 1000 changed rows — a replication data-loss bug (the old
  /// code only ever saw the first 1000 rows of a big table on the first sync).
  Future<PostgrestList> _fetchAll(
      PostgrestFilterBuilder<PostgrestList> builder) async {
    const pageSize = 1000;
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await builder.range(offset, offset + pageSize - 1);
      rows.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return rows;
  }

  /// Splits [items] into consecutive sublists of at most [size] elements.
  Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, min(i + size, items.length));
    }
  }
}

class CloudSyncException implements Exception {
  const CloudSyncException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Regulated identifiers that never leave the device. Keys are table names;
/// values are the columns stripped from pushed rows and preserved from the
/// local row across pulls. Kept in sync with `supabase_schema.sql`, which drops
/// these columns from the cloud tables.
const Map<String, Set<String>> cloudSensitiveColumns = {
  'customers': {'bvn', 'nin'},
};

/// Removes [cloudSensitiveColumns] for [table] from [row] so the values never
/// reach the cloud. Nullable values are otherwise pushed explicitly (see the
/// push path) so field-clearing writes propagate.
Map<String, Object?> stripSensitiveColumns(
    String table, Map<String, Object?> row) {
  final sensitive = cloudSensitiveColumns[table];
  if (sensitive == null) return row;
  return {
    for (final entry in row.entries)
      if (!sensitive.contains(entry.key)) entry.key: entry.value,
  };
}

/// Whether [value] is a well-formed `syncTimestamp()` string
/// (`yyyy-MM-ddTHH:mm:ss.SSSZ` UTC, 3-digit millis) that is not dated in the
/// future beyond a small clock-skew tolerance. Remote tombstones must pass this
/// before they are applied, so a crafted or hostile row cannot force deletions.
bool isValidSyncTimestamp(String? value) {
  if (value == null) return false;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
      .hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  if (parsed.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5)))) {
    return false;
  }
  return true;
}

/// Replicated columns that must hold a number (or NULL). A tampered cloud row
/// pushing a string into one of these would crash the strict `(x as num)` casts
/// in the entity `fromMap` methods on the receiving device (e.g.
/// `loan_entity.dart` `amount`).
const Set<String> cloudNumericColumns = {
  'credit_score',
  'amount',
  'interest_rate',
  'insurance_fee',
  'commission',
  'processing_fee',
  'admin_fee',
  'other_charges',
  'duration_days',
  'duration_weeks',
  'daily_payment',
  'weekly_payment',
  'total_repayment',
  'outstanding_balance',
  'custom_collection_amount',
  'paid_amount',
  'balance',
  'is_recurring',
  'is_enabled',
};

/// Replicated columns read back with a strict `as int` cast on the receiving
/// device; only whole integers (or NULL) are safe to write into local SQLite.
const Set<String> cloudIntColumns = {'installment_number'};

/// Enum-typed replicated columns and the exact values the local app writes.
/// Mirrors the API-4 CHECK constraints in `supabase_schema.sql`; the client
/// enforces the same set at the pull boundary so a garbage status cannot reach
/// SQLite and confuse reporting, even before the server constraints are applied.
const Map<String, Map<String, Set<String>>> cloudEnumValues = {
  'customers': {
    'status': {'active', 'closed', 'blacklisted', 'archived'},
  },
  'loans': {
    'loan_type': {'daily', 'weekly'},
    'status': {'active', 'completed', 'defaulted', 'pending', 'cancelled'},
  },
  'repayment_schedule': {
    'status': {'pending', 'paid', 'partial', 'missed'},
  },
  'payments': {
    'status': {'completed', 'reversed'},
    'type': {'partial', 'full', 'overpayment'},
  },
  'savings_transactions': {
    'type': {'deposit', 'withdrawal', 'overpayment'},
  },
};

/// Text columns that are NOT NULL in the schema and must hold a non-empty
/// string. A pulled row with an empty string in one of these would violate the
/// local NOT NULL constraint (or, worse, feed an empty `fullName`/`name` into
/// UI that indexes `[0]` or `DateTime.parse`, crashing the receiving device).
/// Mirrors the `text not null` columns in `supabase_schema.sql`.
const Map<String, Set<String>> cloudRequiredTextColumns = {
  'customers': {'full_name', 'phone', 'date_registered'},
  'customer_groups': {'name', 'created_at'},
};

/// Whether a pulled row may be written into the local database. Enforces the
/// same typing the entity `fromMap` methods assume — numeric columns are
/// finite non-negative numbers (NaN/±Infinity are `num` but would be stored
/// as NULL or corrupt aggregates, and Infinity even passes the server
/// `>= 0` CHECK), `installment_number` is an integer, enum columns hold known
/// values, and NOT NULL text columns (`full_name`, `phone`, `name`, …) are
/// non-empty strings — and requires a well-formed non-future `updated_at`
/// (API-3 LWW-poisoning guard) plus a sane primary key. Malformed or
/// future-dated rows are skipped and counted as failures, so a hostile cloud
/// row can neither poison the merge nor crash the app later, and a partial
/// pull is never reported as clean.
bool isSaneCloudRow(String table, Map<String, Object?> row, String pk) {
  final id = row[pk];
  if (id == null) return false;
  if (id is String && (id.isEmpty || id.length > 64)) return false;
  if (!isValidSyncTimestamp(row['updated_at'] as String?)) return false;
  for (final column in cloudNumericColumns) {
    final value = row[column];
    if (value == null) continue;
    if (value is! num || !value.isFinite || value < 0) return false;
  }
  for (final column in cloudIntColumns) {
    final value = row[column];
    if (value == null) continue;
    if (value is! int) return false;
  }
  // N2-class guard for sync: loan durations are capped at the same limit the
  // save path enforces (`AppConstants.maxLoanDuration`). A pulled row with a
  // huge duration passes the `num` typing above but would make
  // `CurrencyUtils.splitEvenly`/`LoanScheduleCalculator` allocate unbounded
  // installments on the next `rebuildAllSchedules` (the local N2 OOM, now
  // reachable via sync). `duration_days`/`duration_weeks` are INTEGER in the
  // cloud schema, so a whole int is expected.
  if (table == 'loans') {
    for (final column in const ['duration_days', 'duration_weeks']) {
      final value = row[column];
      if (value == null) continue;
      if (value is! int ||
          value < 1 ||
          value > AppConstants.maxLoanDuration) {
        return false;
      }
    }
  }
  final enums = cloudEnumValues[table];
  if (enums != null) {
    for (final entry in enums.entries) {
      final value = row[entry.key];
      if (value == null) continue;
      if (value is! String || !entry.value.contains(value)) return false;
    }
  }
  final requiredText = cloudRequiredTextColumns[table];
  if (requiredText != null) {
    for (final column in requiredText) {
      final value = row[column];
      if (value == null) return false;
      if (value is! String || value.trim().isEmpty) return false;
    }
  }
  return true;
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

/// Canonical ordering for a group of same-phone non-archived customers: the
/// survivor is the earliest `date_registered` (ties broken by `id`). Both are
/// purely replicated values, so every device resolves the SAME survivor and the
/// merge converges instead of two devices deleting each other's record.
/// `@visibleForTesting` so the determinism rule is pinned by a unit test.
@visibleForTesting
void sortDuplicateCustomersByCanonicalOrder(List<Map<String, Object?>> group) {
  group.sort((a, b) {
    final byDate = ((a['date_registered'] as String?) ?? '')
        .compareTo((b['date_registered'] as String?) ?? '');
    if (byDate != 0) return byDate;
    return ((a['id'] as String?) ?? '').compareTo((b['id'] as String?) ?? '');
  });
}

/// Nullable, non-identity profile columns that may be copied from a duplicate
/// customer onto the survivor when the survivor's value is NULL. Identity
/// columns (`phone`, `nin`, `bvn`, `full_name`, `status`, `date_registered`,
/// `group_id`, `updated_at`) are deliberately excluded — the survivor keeps its
/// own identity, and copying a regulated identifier (`nin`/`bvn`, handled
/// separately with a uniqueness guard) or a `phone` could violate the v21
/// partial unique indexes.
const List<String> _mergeableCustomerFields = [
  'gender',
  'dob',
  'alt_phone',
  'email',
  'residential_address',
  'business_address',
  'occupation',
  'employer',
  'marital_status',
  'nationality',
  'state',
  'lga',
  'next_of_kin',
  'next_of_kin_relation',
  'next_of_kin_phone',
  'guarantor_1_name',
  'guarantor_1_phone',
  'guarantor_1_address',
  'guarantor_2_name',
  'guarantor_2_phone',
  'guarantor_2_address',
  'id_type',
  'id_number',
  'notes',
  'passport_path',
  'guarantor_passport_path',
  'signature_path',
];

/// Merges [duplicate] into [survivor] in one transaction:
///
///  1. re-points every child row (`loans`, `payments`, `documents`,
///     `savings_accounts`, and transitively `repayment_schedule` /
///     `savings_transactions`) at the survivor — the sync trigger stamps each
///     UPDATE so the correction is pushed;
///  2. folds the duplicate's savings balance into the survivor's account when
///     both hold one (the `savings_accounts.customer_id` UNIQUE constraint
///     forbids a plain re-point);
///  3. fills NULL profile fields on the survivor from the duplicate
///     (best-effort, never overwriting an existing value; `nin`/`bvn` are only
///     copied when no other non-archived customer holds the same value);
///  4. hard-deletes the duplicate — the AFTER DELETE sync trigger records the
///     tombstone so the cloud and the other owner's device converge to the
///     survivor too.
///
/// Idempotent and safe to re-run: rows already re-pointed are no-ops and the
/// duplicate is only deleted once. `@visibleForTesting` because the merge is
/// pure DB work — only [_CloudSyncService._resolveDuplicateCustomers]
/// orchestrates it.
@visibleForTesting
Future<void> mergeDuplicateCustomerInto(
  Database db,
  Map<String, Object?> duplicate,
  Map<String, Object?> survivor,
) async {
  final dupId = duplicate['id'] as String?;
  final survivorId = survivor['id'] as String?;
  if (dupId == null || survivorId == null || dupId == survivorId) return;
  await db.transaction((txn) async {
    await txn.update('loans', {'customer_id': survivorId},
        where: 'customer_id = ?', whereArgs: [dupId]);
    await txn.update('payments', {'customer_id': survivorId},
        where: 'customer_id = ?', whereArgs: [dupId]);
    await txn.update('documents', {'customer_id': survivorId},
        where: 'customer_id = ?', whereArgs: [dupId]);

    // Savings account is 1:1 with customers (UNIQUE customer_id), so a plain
    // re-point would conflict when both records hold an account.
    final dupAccountRows = await txn.query('savings_accounts',
        where: 'customer_id = ?', whereArgs: [dupId], limit: 1);
    final survivorAccountRows = await txn.query('savings_accounts',
        where: 'customer_id = ?', whereArgs: [survivorId], limit: 1);
    if (dupAccountRows.isNotEmpty) {
      if (survivorAccountRows.isEmpty) {
        await txn.update('savings_accounts', {'customer_id': survivorId},
            where: 'id = ?', whereArgs: [dupAccountRows.first['id']]);
      } else {
        final dupAccountId = dupAccountRows.first['id'];
        final survivorAccountId = survivorAccountRows.first['id'];
        await txn.update(
            'savings_transactions', {'savings_account_id': survivorAccountId},
            where: 'savings_account_id = ?', whereArgs: [dupAccountId]);
        final dupBalance =
            (dupAccountRows.first['balance'] as num?)?.toDouble() ?? 0.0;
        if (dupBalance != 0.0) {
          await txn.rawUpdate(
            'UPDATE savings_accounts SET balance = balance + ? WHERE id = ?',
            [dupBalance, survivorAccountId],
          );
        }
        await txn.delete('savings_accounts',
            where: 'id = ?', whereArgs: [dupAccountId]);
      }
    }

    // Group membership: fill a gap on the survivor, never overwrite.
    final dupGroup = duplicate['group_id'] as String?;
    if (dupGroup != null &&
        dupGroup.isNotEmpty &&
        (survivor['group_id'] as String?) == null) {
      await txn.update('customers', {'group_id': dupGroup},
          where: 'id = ?', whereArgs: [survivorId]);
    }

    // Profile fields: copy the duplicate's value only where the survivor's is
    // NULL so existing data is never overwritten.
    final fills = <String, Object?>{};
    for (final column in _mergeableCustomerFields) {
      final dupValue = duplicate[column];
      if (dupValue != null && survivor[column] == null) {
        fills[column] = dupValue;
      }
    }
    final dupScore = (duplicate['credit_score'] as num?)?.toDouble() ?? 0.0;
    final survivorScore =
        (survivor['credit_score'] as num?)?.toDouble() ?? 0.0;
    if (dupScore > 0 && survivorScore <= 0) fills['credit_score'] = dupScore;
    for (final column in const ['nin', 'bvn']) {
      final dupValue = duplicate[column];
      if (dupValue == null) continue;
      if (survivor[column] != null) continue;
      // The duplicate itself is still in the table at this point (deleted at
      // the end of the transaction), so it must be excluded from the clash
      // scan or the copy is always skipped.
      final clash = await txn.query('customers',
          columns: const ['id'],
          where: "$column = ? AND id NOT IN (?, ?) AND status != 'archived'",
          whereArgs: [dupValue, survivorId, dupId],
          limit: 1);
      if (clash.isEmpty) fills[column] = dupValue;
    }
    if (fills.isNotEmpty) {
      await txn.update('customers', fills,
          where: 'id = ?', whereArgs: [survivorId]);
    }

    // Remove the duplicate. All children were re-pointed above, so the
    // ON DELETE CASCADE has nothing to clean up; the sync trigger records the
    // tombstone so the removal replicates.
    await txn.delete('customers', where: 'id = ?', whereArgs: [dupId]);
  });
}
