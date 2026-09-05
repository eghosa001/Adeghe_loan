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

class CloudSyncResult {
  const CloudSyncResult({this.pushedRows=0,this.pulledRows=0,this.deletedRows=0,this.mergedCustomers=0,this.error});
  final int pushedRows,pulledRows,deletedRows,mergedCustomers; final String? error;
  bool get success=>error==null;
}

class CloudSyncService {
  CloudSyncService(this._databaseService); final DatabaseService _databaseService;
  Future<void> Function()? onPullComplete;
  static const String _pullFlagKey='pull_in_progress';
  static const int _maxRemoteTombstonesPerCycle=500;
  static const Duration _minAutoSyncInterval=Duration(minutes:2);
  static const List<String> _tables=['business_profile','customer_groups','customers','loans','payments','savings_accounts','savings_transactions','documents','holidays'];
  static const Map<String,String> _tablePrimaryKeys={'business_profile':'id','customer_groups':'id','customers':'id','loans':'id','payments':'id','savings_accounts':'id','savings_transactions':'id','documents':'id','holidays':'id'};
  DateTime? _lastAutoSyncAt; bool _syncing=false;
  bool get isSyncing=>_syncing; bool get isConfigured=>SupabaseConfig.isConfigured;
  bool get isSignedIn{try{return Supabase.instance.client.auth.currentUser!=null;}catch(_){return false;}}
  Future<bool> _isOwner()async{try{return await Supabase.instance.client.rpc('is_owner')==true;}catch(_){return false;}}
  Future<void> syncIfSignedIn()async{try{if(!isConfigured||!isSignedIn)return;final now=DateTime.now();if(_lastAutoSyncAt!=null&&now.difference(_lastAutoSyncAt!)<_minAutoSyncInterval)return;_lastAutoSyncAt=now;await fullSync();}catch(_) {}}
  Future<DateTime?> lastSyncTime()async{final db=await _databaseService.database;final r=await db.query('sync_meta',where:'id = ?',whereArgs:[1],limit:1);if(r.isEmpty)return null;return DateTime.tryParse(r.first['last_pulled_at'] as String? ?? '');}

  Future<CloudSyncResult> fullSync()async{
    if(_syncing)return const CloudSyncResult(error:'A sync is already in progress.');
    if(!isConfigured)return const CloudSyncResult(error:'Supabase is not configured. Add your project URL and key.');
    if(!isSignedIn)return const CloudSyncResult(error:'You are not signed in to the cloud.');
    if(!await _isOwner())return const CloudSyncResult(error:CloudAuthService.notOwnerMessage);
    _syncing=true;
    try{
      final db=await _databaseService.database; await _ensureSyncState(db);
      var pushed=0,pulled=0,deleted=0,attempted=0,pushFailures=0,pullFailures=0,mergedCustomers=0;String? firstError;final failedTables=<String>{};
      try{final r=await _push(db);pushed=r.pushed;deleted=r.deleted;attempted=r.attempted;pushFailures=r.failures;mergedCustomers=r.merged;failedTables.addAll(r.failedTables);}catch(e){firstError=e.toString();}
      try{final r=await _pull(db);pulled=r.pulled;pullFailures=r.failures;}catch(e){firstError??=e.toString();}
      try{await onPullComplete?.call();}catch(_){ }
      String? error=firstError;
      if(error==null&&(pushFailures>0||pullFailures>0)){final f=failedTables.toList()..sort();error='Sync finished with $pushFailures push and $pullFailures pull failure(s).${f.isEmpty?'':' Tables: ${f.join(', ')}.'} Failed work remains queued for retry.';}
      else if(error==null&&attempted>0&&pushed==0&&pulled==0&&deleted==0)error='Nothing was replicated. Check the network and owner access, then try again.';
      return CloudSyncResult(pushedRows:pushed,pulledRows:pulled,deletedRows:deleted,mergedCustomers:mergedCustomers,error:error);
    }finally{_syncing=false;}
  }

  Future<void> _ensureSyncState(Database db)async{
    for(final table in _tables){
      final columns=await db.rawQuery('PRAGMA table_info($table)');
      if(!columns.any((c)=>c['name']=='sync_version'))await db.execute('ALTER TABLE $table ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
      if(!columns.any((c)=>c['name']=='sync_dirty'))await db.execute('ALTER TABLE $table ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_dirty ON $table(sync_dirty)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_${table}_sync_version ON $table(sync_version)');
      final pk=_tablePrimaryKeys[table]!;
      await db.execute("DROP TRIGGER IF EXISTS trg_v25_${table}_dirty_insert");
      await db.execute("DROP TRIGGER IF EXISTS trg_v25_${table}_dirty_update");
      await db.execute("CREATE TRIGGER trg_v25_${table}_dirty_insert AFTER INSERT ON $table WHEN (SELECT value FROM sync_flags WHERE key = '$_pullFlagKey') != '1' AND NEW.sync_dirty = 0 BEGIN UPDATE $table SET sync_dirty=1 WHERE $pk=NEW.$pk; END");
      await db.execute("CREATE TRIGGER trg_v25_${table}_dirty_update AFTER UPDATE ON $table WHEN (SELECT value FROM sync_flags WHERE key = '$_pullFlagKey') != '1' AND NEW.sync_dirty = 0 BEGIN UPDATE $table SET sync_dirty=1 WHERE $pk=NEW.$pk; END");
      await db.execute("DROP TRIGGER IF EXISTS trg_v25_${table}_delete");
      await db.execute("CREATE TRIGGER trg_v25_${table}_delete AFTER DELETE ON $table WHEN (SELECT value FROM sync_flags WHERE key = '$_pullFlagKey') != '1' BEGIN INSERT OR REPLACE INTO sync_tombstones(deleted_table,deleted_row_id,deleted_at,sync_version,sync_dirty) VALUES ('$table',OLD.$pk,COALESCE(OLD.updated_at, '${syncTimestamp()}'),COALESCE(OLD.sync_version,0),1); END");
    }
    final tc=await db.rawQuery('PRAGMA table_info(sync_tombstones)');
    if(!tc.any((c)=>c['name']=='sync_version'))await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 0');
    if(!tc.any((c)=>c['name']=='sync_dirty'))await db.execute('ALTER TABLE sync_tombstones ADD COLUMN sync_dirty INTEGER NOT NULL DEFAULT 1');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_tombstones_sync_version ON sync_tombstones(sync_version)');
    final mc=await db.rawQuery('PRAGMA table_info(sync_meta)');
    if(!mc.any((c)=>c['name']=='last_pulled_version'))await db.execute('ALTER TABLE sync_meta ADD COLUMN last_pulled_version INTEGER NOT NULL DEFAULT 0');
  }

  Future<CloudSyncResult> forceFullReupload()async{final db=await _databaseService.database;await _ensureSyncState(db);await db.update('sync_meta',{'last_pushed_at':null,'last_pulled_version':0},where:'id = ?',whereArgs:[1]);for(final t in _tables)await db.update(t,{'sync_dirty':1});await db.update('sync_tombstones',{'sync_dirty':1});return fullSync();}

  Future<({int pushed,int deleted,int attempted,int failures,int merged,Set<String> failedTables})> _push(Database db)async{
    final client=Supabase.instance.client;final merged=await _resolveDuplicateCustomers(db);final snapshots=<String,List<Map<String,Object?>>>{};
    for(final table in _tables)snapshots[table]=await db.query(table,where:'sync_dirty = 1 OR sync_version = 0');
    final tombstones=await db.query('sync_tombstones',where:'sync_dirty = 1 OR sync_version = 0');
    var pushed=0,deleted=0,attempted=tombstones.length,failures=0;final failedTables=<String>{};
    Future<void> reconcile(String table,Map<String,Object?> serverRow)async{final pk=_tablePrimaryKeys[table]!;final id=serverRow[pk];if(id==null)throw StateError('Missing $pk from cloud response for $table.');final local=await db.query(table,where:'$pk = ?',whereArgs:[id],limit:1);if(local.isEmpty)return;final row=Map<String,Object?>.from(serverRow);final sensitive=cloudSensitiveColumns[table];if(sensitive!=null)for(final c in sensitive)row[c]=local.first[c];row['sync_dirty']=0;await _setPullFlag(db,true);try{await db.insert(table,row,conflictAlgorithm:ConflictAlgorithm.replace);}finally{await _setPullFlag(db,false);}}
    for(final table in _tables){
      final rows=snapshots[table]??const [];if(rows.isEmpty)continue;attempted+=rows.length;
      if(table=='documents'){
        for(final row in rows){
          try{final serverRow=await _pushDocument(client,row);await reconcile('documents',serverRow);pushed++;}
          catch(_){failures++;failedTables.add(table);}
        }
        continue;
      }
      try{final cleaned=[for(final r in rows)stripSensitiveColumns(table,r)];for(final batch in _chunk(cleaned,200)){final result=await client.from(table).upsert(batch,onConflict:_tablePrimaryKeys[table]!).select();if(result.length!=batch.length)throw StateError('Cloud returned ${result.length}/${batch.length} rows for $table.');for(final r in result)await reconcile(table,Map<String,Object?>.from(r));pushed+=batch.length;}}catch(_){failures++;failedTables.add(table);}
    }
    for(final t in tombstones){final table=t['deleted_table'] as String?;final id=t['deleted_row_id'] as String?;final base=(t['sync_version'] as num?)?.toInt()??0;if(table==null||id==null||_tablePrimaryKeys[table]==null){failures++;continue;}try{final result=await client.rpc('apply_sync_tombstone',params:{'p_table':table,'p_row_id':id,'p_base_version':base});if(result is! List||result.isEmpty)throw StateError('Invalid tombstone RPC response.');final applied=result.first is Map&&result.first['applied']==true;await db.delete('sync_tombstones',where:'deleted_table = ? AND deleted_row_id = ?',whereArgs:[table,id]);pushed++;if(applied)deleted++;}catch(_){failures++;failedTables.add(table);}}
    if(failures==0)await _writeMeta(db,pushedAt:_isoUtcNow());return(pushed:pushed,deleted:deleted,attempted:attempted,failures:failures,merged:merged,failedTables:failedTables);
  }

  Future<Map<String,Object?>> _pushDocument(SupabaseClient client,Map<String,Object?> row)async{
    final id=row['id'] as String?;final customerId=row['customer_id'] as String?;final path=row['file_path'] as String?;
    if(id==null||customerId==null||customerId.isEmpty||path==null||path.isEmpty||!await File(path).exists())throw StateError('Document file is missing.');
    final remote=await client.from('documents').select('id,sync_version').eq('id',id).maybeSingle();
    final remoteVersion=(remote?['sync_version'] as num?)?.toInt()??0;final localVersion=(row['sync_version'] as num?)?.toInt()??0;
    if(remoteVersion>localVersion)throw StateError('Remote document is newer.');
    final bytes=await File(path).readAsBytes();
    await client.storage.from(SupabaseConfig.documentsBucket).uploadBinary(_documentStoragePath(customerId,id),bytes,fileOptions:const FileOptions(upsert:true));
    final cleaned=Map<String,Object?>.from(row)..['file_path']='';
    final result=await client.from('documents').upsert(stripSensitiveColumns('documents',cleaned),onConflict:'id').select();
    if(result.length!=1)throw StateError('Cloud did not accept document row.');
    return Map<String,Object?>.from(result.first);
  }

  Future<({int pulled,int failures})> _pull(Database db)async{
    final client=Supabase.instance.client;var cursor=await _readPullVersion(db);var pulled=0,failures=0,batchMax=cursor;await _setPullFlag(db,true);
    try{
      final remoteTombstones=await _fetchAll(client.from('sync_tombstones').select().gt('sync_version',cursor).order('sync_version'));for(final t in remoteTombstones.take(_maxRemoteTombstonesPerCycle)){final table=t['deleted_table'] as String?;final id=t['deleted_row_id'] as String?;final v=(t['sync_version'] as num?)?.toInt()??0;if(!_isValidTombstone(table,id,t['deleted_at']))continue;final pk=_tablePrimaryKeys[table]!;try{final local=await db.query(table,columns:[pk,'sync_version'],where:'$pk = ?',whereArgs:[id],limit:1);final lv=local.isEmpty?0:((local.first['sync_version'] as num?)?.toInt()??0);if(v>lv)await db.delete(table,where:'$pk = ?',whereArgs:[id]);if(v>batchMax)batchMax=v;}catch(_){failures++;}}
      for(final table in _tables){final pk=_tablePrimaryKeys[table]!;final remoteRows=await _fetchAll(client.from(table).select().gt('sync_version',cursor).order('sync_version'));if(remoteRows.isEmpty)continue;final localRows=<String,Map<String,Object?>>{};final ids=remoteRows.map((r)=>r[pk]).whereType<String>().toSet().toList();for(final chunk in _chunk(ids,400)){final ph=List.filled(chunk.length,'?').join(',');for(final r in await db.query(table,where:'$pk IN ($ph)',whereArgs:chunk))localRows[r[pk] as String]=r;}
        for(final remote in remoteRows){final id=remote[pk];final v=(remote['sync_version'] as num?)?.toInt()??0;if(id==null||!isSaneCloudRow(table,remote,pk)){failures++;continue;}try{final local=localRows[id];final lv=local==null?0:((local['sync_version'] as num?)?.toInt()??0);if(v<=lv){if(v>batchMax)batchMax=v;continue;}
          if(table=='customers'){final gid=remote['group_id'] as String?;if(gid!=null&&gid.isNotEmpty&&(await db.query('customer_groups',where:'id = ?',whereArgs:[gid],limit:1)).isEmpty)throw StateError('Parent customer group missing.');}
          else if(table=='loans'){final cid=remote['customer_id'] as String?;if(cid==null||(await db.query('customers',where:'id = ?',whereArgs:[cid],limit:1)).isEmpty)throw StateError('Parent customer missing.');}
          else if(table=='payments'){final lid=remote['loan_id'] as String?;final cid=remote['customer_id'] as String?;if(lid==null||cid==null||(await db.query('loans',where:'id = ?',whereArgs:[lid],limit:1)).isEmpty||(await db.query('customers',where:'id = ?',whereArgs:[cid],limit:1)).isEmpty)throw StateError('Payment parent missing.');}
          else if(table=='documents'){final cid=remote['customer_id'] as String?;if(cid==null||(await db.query('customers',where:'id = ?',whereArgs:[cid],limit:1)).isEmpty)throw StateError('Document parent missing.');}
          else if(table=='savings_accounts'){final cid=remote['customer_id'] as String?;if(cid==null||(await db.query('customers',where:'id = ?',whereArgs:[cid],limit:1)).isEmpty)throw StateError('Savings parent missing.');}
          else if(table=='savings_transactions'){final aid=remote['savings_account_id'] as String?;if(aid==null||(await db.query('savings_accounts',where:'id = ?',whereArgs:[aid],limit:1)).isEmpty)throw StateError('Savings account parent missing.');}
          final row=Map<String,Object?>.from(remote)..['sync_dirty']=0;final sensitive=cloudSensitiveColumns[table];if(sensitive!=null&&local!=null)for(final c in sensitive)row[c]=local[c];if(table=='customers')for(final c in const ['full_name','next_of_kin','guarantor_1_name','guarantor_2_name']){final value=row[c];if(value is String)row[c]=value.trim().toUpperCase();}if(table=='documents')await _materializeDocument(row);await db.insert(table,row,conflictAlgorithm:ConflictAlgorithm.replace);pulled++;if(v>batchMax)batchMax=v;
        }catch(_){failures++;}}
      }
      if(failures==0){await _writePullVersion(db,batchMax);await _writeMeta(db,pulledAt:_isoUtcNow());}
    }finally{await _setPullFlag(db,false);}return(pulled:pulled,failures:failures);
  }

  bool _isValidTombstone(String? table,String? id,Object? deletedAt){if(table==null||id==null||_tablePrimaryKeys[table]==null)return false;if(id.isEmpty||id.length>64)return false;return isValidSyncTimestamp(deletedAt as String?);}
  Future<void> _materializeDocument(Map<String,Object?> row)async{final id=row['id'] as String?;final customerId=row['customer_id'] as String?;if(id==null||customerId==null)throw StateError('Invalid remote document identity.');final bytes=await Supabase.instance.client.storage.from(SupabaseConfig.documentsBucket).download(_documentStoragePath(customerId,id));row['file_path']=await _writeSecureDocument(bytes);}
  Future<String> _writeSecureDocument(List<int> bytes)async{final root=await getApplicationDocumentsDirectory();final directory=Directory('${root.path}${Platform.pathSeparator}secure_documents');if(!await directory.exists())await directory.create(recursive:true);final path='${directory.path}${Platform.pathSeparator}${const Uuid().v4()}.enc';await File(path).writeAsBytes(bytes,flush:true);if(Platform.isWindows){try{final user=Platform.environment['USERNAME']??'';if(user.isNotEmpty)await Process.run('icacls',[path,'/inheritance:r','/grant:r','$user:R']);}catch(_){}}return path;}
  String _documentStoragePath(String customerId,String documentId)=>'${sanitizeCloudPathPart(customerId)}/${sanitizeCloudPathPart(documentId)}.enc';
  Future<int> _readPullVersion(Database db)async{final rows=await db.query('sync_meta',where:'id = ?',whereArgs:[1],limit:1);if(rows.isEmpty)return 0;return((rows.first['last_pulled_version'] as num?)?.toInt()??0);}
  Future<void> _writePullVersion(Database db,int version)async{await db.update('sync_meta',{'last_pulled_version':version},where:'id = ?',whereArgs:[1]);}
  Future<void> _writeMeta(Database db,{String? pushedAt,String? pulledAt})async{final v=<String,Object?>{};if(pushedAt!=null)v['last_pushed_at']=pushedAt;if(pulledAt!=null)v['last_pulled_at']=pulledAt;if(v.isNotEmpty)await db.update('sync_meta',v,where:'id = ?',whereArgs:[1]);}
  Future<void> _setPullFlag(Database db,bool value)async{await db.insert('sync_flags',{'key':_pullFlagKey,'value':value?'1':'0'},conflictAlgorithm:ConflictAlgorithm.replace);}
  String _isoUtcNow()=>syncTimestamp();
  Future<PostgrestList> _fetchAll(PostgrestFilterBuilder<PostgrestList> builder)async{const pageSize=1000;final rows=<Map<String,dynamic>>[];for(var offset=0;;offset+=pageSize){final page=await builder.range(offset,offset+pageSize-1);rows.addAll(page);if(page.length<pageSize)break;}return rows;}
  Iterable<List<T>> _chunk<T>(List<T> items,int size)sync*{for(var i=0;i<items.length;i+=size)yield items.sublist(i,min(i+size,items.length));}
  Future<int> _resolveDuplicateCustomers(Database db)async{final rows=await db.query('customers',where:"status != 'archived'");final byPhone=<String,List<Map<String,Object?>>>{};for(final row in rows){final p=(row['phone'] as String?)?.trim();if(p==null||p.isEmpty)continue;byPhone.putIfAbsent(p,()=>[]).add(row);}var merged=0;for(final g in byPhone.values){if(g.length<2)continue;sortDuplicateCustomersByCanonicalOrder(g);for(final d in g.skip(1)){await mergeDuplicateCustomerInto(db,d,g.first);merged++;}}return merged;}
}

class CloudSyncException implements Exception{const CloudSyncException(this.message);final String message;@override String toString()=>message;}
const Map<String,Set<String>> cloudSensitiveColumns={'customers':{'bvn','nin'}};
Map<String,Object?> stripSensitiveColumns(String table,Map<String,Object?> row){final sensitive=cloudSensitiveColumns[table];if(sensitive==null)return row;return{for(final e in row.entries)if(!sensitive.contains(e.key))e.key:e.value};}
bool isValidSyncTimestamp(String? value){if(value==null)return false;if(!RegExp(r'^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$').hasMatch(value))return false;final parsed=DateTime.tryParse(value);if(parsed==null)return false;if(parsed.isAfter(DateTime.now().toUtc().add(const Duration(minutes:5))))return false;return true;}
const Set<String> cloudNumericColumns={'credit_score','amount','interest_rate','insurance_fee','commission','processing_fee','admin_fee','other_charges','duration_days','duration_weeks','daily_payment','weekly_payment','total_repayment','outstanding_balance','custom_collection_amount','paid_amount','balance','is_recurring','is_enabled'};
const Set<String> cloudIntColumns={'installment_number'};
const Map<String,Map<String,Set<String>>> cloudEnumValues={'customers':{'status':{'active','closed','blacklisted','archived'}},'loans':{'loan_type':{'daily','weekly'},'status':{'active','completed','defaulted','pending','cancelled'}},'repayment_schedule':{'status':{'pending','paid','partial','missed'}},'payments':{'status':{'completed','reversed'},'type':{'partial','full','overpayment'}},'savings_transactions':{'type':{'deposit','withdrawal','overpayment'}}};
const Map<String,Set<String>> cloudRequiredTextColumns={'customers':{'full_name','phone','date_registered'},'customer_groups':{'name','created_at'}};
bool isSaneCloudRow(String table,Map<String,Object?> row,String pk){final id=row[pk];if(id==null)return false;if(id is String&&(id.isEmpty||id.length>64))return false;if(!isValidSyncTimestamp(row['updated_at'] as String?))return false;final version=row['sync_version'];if(version is! num||!version.isFinite||version<1)return false;for(final c in cloudNumericColumns){final v=row[c];if(v==null)continue;if(v is! num||!v.isFinite||v<0)return false;}for(final c in cloudIntColumns){final v=row[c];if(v!=null&&v is! int)return false;}if(table=='loans')for(final c in const ['duration_days','duration_weeks']){final v=row[c];if(v!=null&&(v is! int||v<1||v>AppConstants.maxLoanDuration))return false;}final enums=cloudEnumValues[table];if(enums!=null)for(final e in enums.entries){final v=row[e.key];if(v!=null&&(v is! String||!e.value.contains(v)))return false;}final req=cloudRequiredTextColumns[table];if(req!=null)for(final c in req){final v=row[c];if(v is! String||v.trim().isEmpty)return false;}return true;}
String sanitizeCloudPathPart(String value){final sanitized=value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'),'_');return sanitized.isEmpty?'_':sanitized;}
@visibleForTesting bool shouldApplyRemoteTombstone(String? localUpdatedAt,String deletedAt){if(localUpdatedAt==null)return true;return localUpdatedAt.compareTo(deletedAt)<0;}
@visibleForTesting void sortDuplicateCustomersByCanonicalOrder(List<Map<String,Object?>> group){group.sort((a,b){final d=((a['date_registered'] as String?)??'').compareTo((b['date_registered'] as String?)??'');if(d!=0)return d;return((a['id'] as String?)??'').compareTo((b['id'] as String?)??'');});}
const List<String> _mergeableCustomerFields=['gender','dob','alt_phone','email','residential_address','business_address','occupation','employer','marital_status','nationality','state','lga','next_of_kin','next_of_kin_relation','next_of_kin_phone','guarantor_1_name','guarantor_1_phone','guarantor_1_address','guarantor_2_name','guarantor_2_phone','guarantor_2_address','id_type','id_number','notes','passport_path','guarantor_passport_path','signature_path'];
@visibleForTesting Future<void> mergeDuplicateCustomerInto(Database db,Map<String,Object?> duplicate,Map<String,Object?> survivor)async{final dupId=duplicate['id'] as String?;final survivorId=survivor['id'] as String?;if(dupId==null||survivorId==null||dupId==survivorId)return;await db.transaction((txn)async{final at=syncTimestamp();await txn.update('loans',{'customer_id':survivorId,'updated_at':at},where:'customer_id = ?',whereArgs:[dupId]);await txn.update('payments',{'customer_id':survivorId,'updated_at':at},where:'customer_id = ?',whereArgs:[dupId]);await txn.update('documents',{'customer_id':survivorId,'updated_at':at},where:'customer_id = ?',whereArgs:[dupId]);final da=await txn.query('savings_accounts',where:'customer_id = ?',whereArgs:[dupId],limit:1);final sa=await txn.query('savings_accounts',where:'customer_id = ?',whereArgs:[survivorId],limit:1);if(da.isNotEmpty){if(sa.isEmpty)await txn.update('savings_accounts',{'customer_id':survivorId,'updated_at':at},where:'id = ?',whereArgs:[da.first['id']]);else{final did=da.first['id'];final sid=sa.first['id'];await txn.update('savings_transactions',{'savings_account_id':sid,'updated_at':at},where:'savings_account_id = ?',whereArgs:[did]);final bal=(da.first['balance'] as num?)?.toDouble()??0;if(bal!=0)await txn.rawUpdate('UPDATE savings_accounts SET balance=balance+?,updated_at=? WHERE id=?',[bal,at,sid]);await txn.delete('savings_accounts',where:'id = ?',whereArgs:[did]);}}final fills=<String,Object?>{};for(final c in _mergeableCustomerFields)if(duplicate[c]!=null&&survivor[c]==null)fills[c]=duplicate[c];final ds=(duplicate['credit_score'] as num?)?.toDouble()??0;final ss=(survivor['credit_score'] as num?)?.toDouble()??0;if(ds>0&&ss<=0)fills['credit_score']=ds;if((survivor['group_id'] as String?)==null&&(duplicate['group_id'] as String?)?.isNotEmpty==true)fills['group_id']=duplicate['group_id'];if(fills.isNotEmpty){fills['updated_at']=at;await txn.update('customers',fills,where:'id = ?',whereArgs:[survivorId]);}await txn.delete('customers',where:'id = ?',whereArgs:[dupId]);});}