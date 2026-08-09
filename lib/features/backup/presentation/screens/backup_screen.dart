import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:loantrack/core/widgets/empty_state.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';

import '../../../../core/database/database_service.dart';
import '../../../../core/di/providers.dart';
import '../../data/backup_service.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<List<File>> _backupFilesFuture;
  bool _isBackupRunning = false;

  BackupService _backupService(DatabaseService dbService) =>
      BackupService(dbService, ref.read(secureStorageProvider));

  Future<List<File>> _loadBackups() async {
    final dbService = await ref.read(databaseServiceProvider.future);
    return _backupService(dbService).listBackups();
  }

  @override
  void initState() {
    super.initState();
    _backupFilesFuture = _loadBackups();
  }

  Future<void> _refreshBackups() async {
    if (!mounted) return;
    setState(() {
      _backupFilesFuture = _loadBackups();
    });
  }

  Future<void> _createBackup() async {
    setState(() => _isBackupRunning = true);
    try {
      final dbService = await ref.read(databaseServiceProvider.future);
      final backup = await _backupService(dbService).createBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup created: ${path.basename(backup.path)}'),
          ),
        );
      }
      await _refreshBackups();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _isBackupRunning = false);
    }
  }

  Future<void> _restoreBackup(File backupFile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          'This will overwrite current app data with ${path.basename(backupFile.path)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final dbService = await ref.read(databaseServiceProvider.future);
      await _backupService(dbService).restoreBackup(backupFile);
      logAuditAction(
        ref,
        'RESTORE',
        'Backup restored from ${path.basename(backupFile.path)}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup restored successfully. Restart app to apply changes.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              icon: _isBackupRunning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Create backup'),
              onPressed: _isBackupRunning ? null : _createBackup,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<File>>(
                future: _backupFilesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Unable to list backups: ${snapshot.error}'),
                    );
                  }
                  final files = snapshot.data ?? [];
                  if (files.isEmpty) {
                    return const EmptyState(
                      icon: Icons.cloud_upload_outlined,
                      title: 'No backups available',
                      subtitle:
                          'Create your first backup to keep your data safe.',
                    );
                  }
                  return KeyboardRefreshable(
                    onRefresh: _refreshBackups,
                    child: ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return ListTile(
                          title: Text(path.basename(file.path)),
                          subtitle: Text(() {
                            try {
                              return file
                                  .lastModifiedSync()
                                  .toLocal()
                                  .toString();
                            } catch (_) {
                              return 'Unknown date';
                            }
                          }()),
                          trailing: IconButton(
                            icon: const Icon(Icons.restore_outlined),
                            onPressed: () => _restoreBackup(file),
                            tooltip: 'Restore backup',
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
