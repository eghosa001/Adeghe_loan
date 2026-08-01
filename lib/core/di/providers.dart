import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';
import '../security/secure_storage_service.dart';
import '../security/file_encryption_service.dart';
import '../database/database_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/customers/data/statement_service.dart';
import '../../features/audit_log/data/audit_log_repository.dart';

final secureStorageProvider = Provider((ref) => SecureStorageService());

final fileEncryptionProvider = Provider<FileEncryptionService>((ref) {
  return FileEncryptionService(ref.read(secureStorageProvider));
});

final storageServiceProvider = Provider((ref) => StorageService());

/// Provides the [DatabaseService] once the app is unlocked.
///
/// Uses `ref.watch(authProvider)` so Riverpod re-runs this provider reactively
/// when auth state changes — no busy-wait polling loop.
final databaseServiceProvider = FutureProvider<DatabaseService>((ref) async {
  final authState = ref.watch(authProvider);
  if (authState == AuthState.unlocked) {
    final secure = ref.read(secureStorageProvider);
    final service = DatabaseService(secure);
    await service.database;
    return service;
  }

  // Suspend until auth state changes. When authProvider changes,
  // Riverpod cancels this future and re-runs the provider.
  return Completer<DatabaseService>().future;
});

final auditLogRepositoryProvider = FutureProvider<AuditLogRepository>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return AuditLogRepository(dbService);
});

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return BackupService(dbService);
});

final statementServiceProvider = FutureProvider<StatementService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return StatementService(dbService);
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// Logs an auditable user action. Safe to call — errors are swallowed.
Future<void> logAuditAction(dynamic ref, String action, String details) async {
  try {
    final repo = await ref.read(auditLogRepositoryProvider.future);
    await repo.log('User', action, details);
  } catch (_) {
    // Audit logging should never block the user flow.
  }
}
