import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logs/logger.dart';
import '../storage/storage_service.dart';
import '../security/secure_storage_service.dart';
import '../security/file_encryption_service.dart';
import '../database/database_service.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

final loggerProvider = Provider((ref) => logger);

final secureStorageProvider = Provider((ref) => SecureStorageService());

final fileEncryptionProvider = Provider<FileEncryptionService>((ref) {
  return FileEncryptionService(ref.read(secureStorageProvider));
});

final storageServiceProvider = Provider((ref) => StorageService());

final databaseServiceProvider = FutureProvider<DatabaseService>((ref) async {
  while (ref.watch(authProvider) != AuthState.unlocked) {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  final secure = ref.read(secureStorageProvider);
  final service = DatabaseService(secure);
  await service.database;
  return service;
});
