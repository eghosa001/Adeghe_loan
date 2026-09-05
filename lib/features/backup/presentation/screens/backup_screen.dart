import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:loantrack/core/widgets/empty_state.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';

import '../../../../core/database/database_service.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/security/secure_storage_service.dart';
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
    setState(() => _backupFilesFuture = _loadBackups());
  }

  Future<String?> _askRecoveryPassword({required bool confirm}) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(confirm ? 'Protect portable backup' : 'Recovery password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Recovery password',
                helperText: 'At least 16 characters with letters and numbers',
              ),
            ),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final password = passwordController.text;
              final error = SecureStorageService.recoveryPasswordError(password);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                return;
              }
              if (confirm && password != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
                return;
              }
              Navigator.pop(context, password);
            },
            child: Text(confirm ? 'Create backup' : 'Restore'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  Future<void> _createBackup() async {
    setState(() => _isBackupRunning = true);
    try {
      final password = await _askRecoveryPassword(confirm: true);
      if (password == null) return;
      final dbService = await ref.read(databaseServiceProvider.future);
      final backup = await _backupService(dbService).createBackup(recoveryPassword: password);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Portable backup created: ${path.basename(backup.path)}')));
      }
      await _refreshBackups();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    } finally {
      if (mounted) setState(() => _isBackupRunning = false);
    }
  }

  Future<void> _restoreBackup(File backupFile) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text('This will overwrite current app data with ${path.basename(backupFile.path)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final raw = await backupFile.readAsBytes();
      final portable = BackupService.isPortableContainer(raw);
      final password = portable ? await _askRecoveryPassword(confirm: false) : null;
      if (portable && password == null) return;
      final dbService = await ref.read(databaseServiceProvider.future);
      await _backupService(dbService).restoreBackup(backupFile, recoveryPassword: password);
      logAuditAction(ref, 'RESTORE', 'Backup restored from ${path.basename(backupFile.path)}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored successfully. Restart app to apply changes.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              icon: _isBackupRunning
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: const Text('Create portable backup'),
              onPressed: _isBackupRunning ? null : _createBackup,
            ),
            const SizedBox(height: 8),
            const Text('Portable backups can be restored on a replacement device using the recovery password.'),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<File>>(
                future: _backupFilesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError) return Center(child: Text('Unable to list backups: ${snapshot.error}'));
                  final files = snapshot.data ?? [];
                  if (files.isEmpty) return const EmptyState(icon: Icons.cloud_upload_outlined, title: 'No backups available', subtitle: 'Create your first backup to keep your data safe.');
                  return KeyboardRefreshable(
                    onRefresh: _refreshBackups,
                    child: ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return ListTile(
                          title: Text(path.basename(file.path)),
                          subtitle: Text(() {
                            try { return file.lastModifiedSync().toLocal().toString(); } catch (_) { return 'Unknown date'; }
                          }()),
                          trailing: IconButton(icon: const Icon(Icons.restore_outlined), onPressed: () => _restoreBackup(file), tooltip: 'Restore backup'),
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
