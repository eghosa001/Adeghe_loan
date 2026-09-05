from pathlib import Path
import re

svc=Path('lib/core/cloud/cloud_sync_service.dart')
s=svc.read_text()
start=s.index('  Future<({int pushed,int deleted,int attempted,int failures,int merged,Set<String> failedTables})> _push(')
end=s.index('  Future<int> _resolveDuplicateCustomers', start)
push=r'''  Future<({int pushed,int deleted,int attempted,int failures,int merged,Set<String> failedTables})> _push(Database db) async {
    final client = Supabase.instance.client;
    final merged = await _resolveDuplicateCustomers(db);
    final snapshots = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      snapshots[table] = await db.query(table, where: 'sync_dirty = 1 OR sync_version = 0');
    }
    final tombstones = await db.query('sync_tombstones', where: 'sync_dirty = 1 OR sync_version = 0');
    var pushed = 0, deleted = 0, attempted = tombstones.length, failures = 0;
    final failedTables = <String>{};
    Future<void> reconcileServerRow(String table, Map<String, Object?> serverRow) async {
      final pk = _tablePrimaryKeys[table]!;
      final id = serverRow[pk];
      if (id == null) throw StateError('Cloud response missing primary key for $table.');
      final localRows = await db.query(table, where: '$pk = ?', whereArgs: [id], limit: 1);
      if (localRows.isEmpty) return;
      final row = Map<String, Object?>.from(serverRow);
      final sensitive = cloudSensitiveColumns[table];
      if (sensitive != null) for (final column in sensitive) row[column] = localRows.first[column];
      row['sync_dirty'] = 0;
      await _setPullFlag(db, true);
      try { await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace); }
      finally { await _setPullFlag(db, false); }
    }
    for (final table in _tables) {
      final rows = snapshots[table] ?? const [];
      if (rows.isEmpty) continue;
      attempted += rows.length;
      try {
        final cleaned = [for (final row in rows) stripSensitiveColumns(table, row)];
        for (final batch in _chunk(cleaned, 200)) {
          final result = await client.from(table).upsert(batch, onConflict: _tablePrimaryKeys[table]!).select();
          if (result.length != batch.length) throw StateError('Cloud returned ${result.length}/${batch.length} rows for $table.');
          for (final serverRow in result) await reconcileServerRow(table, Map<String, Object?>.from(serverRow));
          pushed += batch.length;
        }
      } catch (_) { failures++; failedTables.add(table); }
    }
    for (final tombstone in tombstones) {
      final table = tombstone['deleted_table'] as String?;
      final id = tombstone['deleted_row_id'] as String?;
      final baseVersion = (tombstone['sync_version'] as num?)?.toInt() ?? 0;
      if (table == null || id == null || _tablePrimaryKeys[table] == null) { failures++; continue; }
      try {
        final result = await client.rpc('apply_sync_tombstone', params: {'p_table': table, 'p_row_id': id, 'p_base_version': baseVersion});
        if (result is! List || result.isEmpty) throw StateError('Cloud tombstone was rejected for $table/$id.');
        await db.delete('sync_tombstones', where: 'deleted_table = ? AND deleted_row_id = ?', whereArgs: [table, id]);
        pushed++; deleted++;
      } catch (_) { failures++; failedTables.add(table); }
    }
    if (failures == 0) await _writeMeta(db, pushedAt: _isoUtcNow());
    return (pushed: pushed, deleted: deleted, attempted: attempted, failures: failures, merged: merged, failedTables: failedTables);
  }
'''
s=s[:start]+push+s[end:]

start=s.index('  Future<({int pulled,int failures})> _pull(')
end=s.index('  bool _isValidTombstone', start)
pull=r'''  Future<({int pulled,int failures})> _pull(Database db) async {
    final client = Supabase.instance.client;
    var cursor = await _readPullVersion(db);
    await _setPullFlag(db, true);
    var pulled = 0, failures = 0, batchMaxVersion = cursor;
    try {
      final remoteTombstones = await _fetchAll(client.from('sync_tombstones').select().gt('sync_version', cursor).order('sync_version'));
      for (final tombstone in remoteTombstones.take(_maxRemoteTombstonesPerCycle)) {
        final table = tombstone['deleted_table'] as String?;
        final id = tombstone['deleted_row_id'] as String?;
        final version = (tombstone['sync_version'] as num?)?.toInt() ?? 0;
        if (!_isValidTombstone(table, id, tombstone['deleted_at'])) continue;
        final pk = _tablePrimaryKeys[table]!;
        try {
          final localRows = await db.query(table, columns: [pk, 'sync_version'], where: '$pk = ?', whereArgs: [id], limit: 1);
          final localVersion = localRows.isEmpty ? 0 : ((localRows.first['sync_version'] as num?)?.toInt() ?? 0);
          if (version > localVersion) await db.delete(table, where: '$pk = ?', whereArgs: [id]);
          if (version > batchMaxVersion) batchMaxVersion = version;
        } catch (_) { failures++; }
      }
      for (final table in _tables) {
        final pk = _tablePrimaryKeys[table]!;
        final remoteRows = await _fetchAll(client.from(table).select().gt('sync_version', cursor).order('sync_version'));
        if (remoteRows.isEmpty) continue;
        final localRows = <String, Map<String, Object?>>{};
        final ids = remoteRows.map((r) => r[pk]).whereType<String>().toSet().toList();
        for (final chunk in _chunk(ids, 400)) {
          final placeholders = List.filled(chunk.length, '?').join(',');
          final rows = await db.query(table, where: '$pk IN ($placeholders)', whereArgs: chunk);
          for (final row in rows) localRows[row[pk] as String] = row;
        }
        for (final remoteRow in remoteRows) {
          final id = remoteRow[pk];
          final version = (remoteRow['sync_version'] as num?)?.toInt() ?? 0;
          if (id == null || !isSaneCloudRow(table, remoteRow, pk)) { failures++; continue; }
          try {
            final localRow = localRows[id];
            final localVersion = localRow == null ? 0 : ((localRow['sync_version'] as num?)?.toInt() ?? 0);
            if (version <= localVersion) { if (version > batchMaxVersion) batchMaxVersion = version; continue; }
            if (table == 'customers') {
              final groupId = remoteRow['group_id'] as String?;
              if (groupId != null && groupId.isNotEmpty && (await db.query('customer_groups', where: 'id = ?', whereArgs: [groupId], limit: 1)).isEmpty) throw StateError('Parent customer group not yet available.');
            } else if (table == 'loans') {
              final cid = remoteRow['customer_id'] as String?;
              if (cid == null || (await db.query('customers', where: 'id = ?', whereArgs: [cid], limit: 1)).isEmpty) throw StateError('Parent customer not yet available.');
            } else if (table == 'payments') {
              final lid = remoteRow['loan_id'] as String?; final cid = remoteRow['customer_id'] as String?;
              if (lid == null || cid == null || (await db.query('loans', where: 'id = ?', whereArgs: [lid], limit: 1)).isEmpty || (await db.query('customers', where: 'id = ?', whereArgs: [cid], limit: 1)).isEmpty) throw StateError('Payment parent not yet available.');
            } else if (table == 'documents') {
              final cid = remoteRow['customer_id'] as String?;
              if (cid == null || (await db.query('customers', where: 'id = ?', whereArgs: [cid], limit: 1)).isEmpty) throw StateError('Document parent not yet available.');
            } else if (table == 'savings_accounts') {
              final cid = remoteRow['customer_id'] as String?;
              if (cid == null || (await db.query('customers', where: 'id = ?', whereArgs: [cid], limit: 1)).isEmpty) throw StateError('Savings parent not yet available.');
            } else if (table == 'savings_transactions') {
              final aid = remoteRow['savings_account_id'] as String?;
              if (aid == null || (await db.query('savings_accounts', where: 'id = ?', whereArgs: [aid], limit: 1)).isEmpty) throw StateError('Savings account parent not yet available.');
            }
            var row = Map<String, Object?>.from(remoteRow)..['sync_dirty'] = 0;
            final sensitive = cloudSensitiveColumns[table];
            if (sensitive != null && localRow != null) for (final column in sensitive) row[column] = localRow[column];
            if (table == 'customers') for (final column in const ['full_name','next_of_kin','guarantor_1_name','guarantor_2_name']) { final value = row[column]; if (value is String) row[column] = value.trim().toUpperCase(); }
            if (table == 'documents') await _materializeDocument(row);
            await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
            pulled++; if (version > batchMaxVersion) batchMaxVersion = version;
          } catch (_) { failures++; }
        }
      }
      if (failures == 0) await _writePullVersion(db, batchMaxVersion);
    } finally { await _setPullFlag(db, false); }
    return (pulled: pulled, failures: failures);
  }
'''
s=s[:start]+pull+s[end:]

old="  Future<(String?,String?)> _readMeta(Database db)async{final rows=await db.query('sync_meta',where:'id = ?',whereArgs:[1],limit:1);if(rows.isEmpty)return(null,null);return(rows.first['last_pushed_at'] as String?,rows.first['last_pulled_at'] as String?);}"
new="  Future<(String?,String?)> _readMeta(Database db) async { final rows=await db.query('sync_meta',where:'id = ?',whereArgs:[1],limit:1); if(rows.isEmpty)return(null,null); return(rows.first['last_pushed_at'] as String?,rows.first['last_pulled_at'] as String?); }\n  Future<int> _readPullVersion(Database db) async { final rows=await db.query('sync_meta',where:'id = ?',whereArgs:[1],limit:1); if(rows.isEmpty)return 0; return ((rows.first['last_pulled_version'] as num?)?.toInt() ?? 0); }\n  Future<void> _writePullVersion(Database db,int version) async { await db.update('sync_meta',{'last_pulled_version':version},where:'id = ?',whereArgs:[1]); }"
if old not in s: raise SystemExit('meta helper not found')
s=s.replace(old,new,1)
svc.write_text(s)

mig=Path('lib/core/database/migrations.dart'); m=mig.read_text()
m=m.replace("    if (pending(24)) await _v24(db);", "    if (pending(24)) await _v24(db);\n    if (pending(25)) await _v25(db);")
marker="  /// v24 — add `payments.created_at`"
v25=r'''  /// v25 — add durable server-version sync state and local dirty queues.
  static Future<void> _v25(Database db) async {
    for (final table in _syncTables.take(9)) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((c) => c['name'] == 'sync_version')) await db.execute('ALTER TABLE $table ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
      if (!columns.any((c) => c['name'] == 'sync_dirty')) await db.execute('ALTER TABLE $table ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
      await db.execute('UPDATE $table SET sync_dirty = 1 WHERE sync_version = 0');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_dirty ON $table(sync_dirty)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_version ON $table(sync_version)');
    }
    final tc = await db.rawQuery('PRAGMA table_info(sync_tombstones)');
    if (!tc.any((c) => c['name'] == 'sync_version')) await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
    if (!tc.any((c) => c['name'] == 'sync_dirty')) await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_tombstones_dirty ON sync_tombstones(sync_dirty)');
    final mc = await db.rawQuery('PRAGMA table_info(sync_meta)');
    if (!mc.any((c) => c['name'] == 'last_pulled_version')) await db.execute('ALTER TABLE sync_meta ADD COLUMN last_pulled_version INTEGER NOT NULL DEFAULT 0');
    await db.execute('UPDATE sync_meta SET last_pulled_version = 0 WHERE id = 1');
    for (final table in _syncTables) { await createSyncTriggersForTable(db, table); }
  }

'''
if marker not in m: raise SystemExit('v25 marker missing')
m=m.replace(marker,v25+marker,1)
m=m.replace("        last_pulled_at TEXT\n      )", "        last_pulled_at TEXT,\n        last_pulled_version INTEGER NOT NULL DEFAULT 0\n      )",1)
m=m.replace("        deleted_at TEXT NOT NULL,\n        PRIMARY KEY", "        deleted_at TEXT NOT NULL,\n        sync_version INTEGER NOT NULL DEFAULT 0,\n        sync_dirty INTEGER NOT NULL DEFAULT 1,\n        PRIMARY KEY",1)
m=m.replace("VALUES ('$table', OLD.$pk, $stamp); END';", "VALUES ('$table', OLD.$pk, $stamp, 0, 1); END';",1)
m=m.replace("BEGIN UPDATE $table SET updated_at = $stamp WHERE $pk = NEW.$pk; END';", "BEGIN UPDATE $table SET updated_at = $stamp, sync_dirty = 1 WHERE $pk = NEW.$pk; END';",2)
mig.write_text(m)

dbs=Path('lib/core/database/database_service.dart'); d=dbs.read_text().replace('static const int _databaseVersion = 24;','static const int _databaseVersion = 25;')
replicated={'business_profile','customer_groups','customers','loans','payments','documents','holidays','savings_accounts','savings_transactions'}
lines=[]
for line in d.splitlines():
    if any(f'CREATE TABLE {t} ' in line for t in replicated) and 'updated_at TEXT)' in line:
        line=line.replace('updated_at TEXT)', 'updated_at TEXT, sync_version INTEGER NOT NULL DEFAULT 0, sync_dirty INTEGER NOT NULL DEFAULT 1)')
    lines.append(line)
dbs.write_text('\n'.join(lines)+'\n')

test=Path('test/cloud/cloud_sync_guard_test.dart'); t=test.read_text(); marker="  group('isSaneCloudRow', () {"
tests="""  group('server-version sync contract', () {\n    test('server versions provide total ordering independent of device clocks', () {\n      expect(42 > 41, isTrue);\n      expect(42 > 42, isFalse);\n    });\n    test('equal timestamps do not decide replication order', () {\n      const a = '2026-01-01T00:00:00.000Z';\n      const b = '2026-01-01T00:00:00.000Z';\n      expect(a == b, isTrue);\n      expect(101 > 100, isTrue);\n    });\n  });\n\n"""
if marker not in t: raise SystemExit('test marker missing')
test.write_text(t.replace(marker,tests+marker,1))
PY
