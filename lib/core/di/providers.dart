import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/storage_service.dart';
import '../security/secure_storage_service.dart';
import '../security/file_encryption_service.dart';
import '../database/database_service.dart';
import '../cloud/cloud_auth_service.dart';
import '../cloud/cloud_sync_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/backup/data/backup_service.dart';
import '../../features/customers/data/statement_service.dart';
import '../../features/audit_log/data/audit_log_repository.dart';
import '../../features/loans/data/loan_schedule_service.dart';

class _ThemeModeNotifier extends StateNotifier<ThemeMode> {
  _ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _load();
  }

  final SecureStorageService _storage;

  Future<void> _load() async {
    state = await _storage.getThemeMode();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.setThemeMode(mode);
    state = mode;
  }
}

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
    // Each unlock runs this provider body and opens a fresh SQLCipher
    // connection. Without this the previous connection is never closed, so
    // every lock/unlock cycle leaks an open DB handle. On dispose (auth
    // state change) close the memoized connection; the next unlock opens a
    // new one. `withExclusiveAccess` makes close→reopen safe for callers.
    ref.onDispose(() {
      unawaited(service.close());
    });
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
  final secure = ref.read(secureStorageProvider);
  return BackupService(dbService, secure);
});

final statementServiceProvider = FutureProvider<StatementService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  return StatementService(dbService);
});

final cloudAuthServiceProvider = Provider<CloudAuthService>((ref) {
  return CloudAuthService();
});

/// Session-scoped: once the owner chooses "Continue offline" on the pre-entry
/// cloud gate, skip the gate for the rest of this app run (reset on sign-out
/// or when the process restarts). Signing in makes this irrelevant because
/// [CloudAuthService.isSignedIn] short-circuits the gate.
final cloudGateDismissedProvider = StateProvider<bool>((ref) => false);

final cloudSyncServiceProvider = FutureProvider<CloudSyncService>((ref) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  // Reuse the SAME version notifier as `loanScheduleServiceProvider` so the
  // post-pull rebuild refreshes every schedule-reading provider.
  final scheduleService = LoanScheduleService(
      dbService, ref.read(loanScheduleVersionProvider.notifier));
  final service = CloudSyncService(dbService);
  service.onPullComplete = () async {
    try {
      await scheduleService.rebuildAllSchedules();
    } catch (_) {
      // Best-effort: a rebuild failure must not fail the sync cycle.
    }
  };
  return service;
});

final themeModeProvider =
    StateNotifierProvider<_ThemeModeNotifier, ThemeMode>((ref) {
  return _ThemeModeNotifier(ref.read(secureStorageProvider));
});

/// Logs an auditable user action. Safe to call — errors are swallowed.
Future<void> logAuditAction(dynamic ref, String action, String details) async {
  try {
    final repo = await ref.read(auditLogRepositoryProvider.future);
    await repo.log('User', action, details);
  } catch (_) {
    // Audit logging should never block the user flow.
  }
}