import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../business/presentation/providers/business_providers.dart';

/// App-level settings (session timeout, auto-backup) stored in the settings table.
final appSettingsProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final repo = await ref.watch(businessRepoProvider.future);
  final sessionTimeout =
      await repo.getSetting('session_timeout_minutes');
  final autoBackup = await repo.getSetting('auto_backup_enabled');
  return {
    'session_timeout_minutes':
        sessionTimeout ?? AppConstants.defaultInactivityTimeout.inMinutes.toString(),
    'auto_backup_enabled': autoBackup ?? '1',
  };
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _sessionTimeoutLoading = false;

  Future<void> _updateSessionTimeout(int minutes) async {
    setState(() => _sessionTimeoutLoading = true);
    try {
      final repo = await ref.read(businessRepoProvider.future);
      await repo.saveSettings({'session_timeout_minutes': minutes.toString()});
      ref.invalidate(appSettingsProvider);
      // Apply the new timeout immediately (main.dart watches this provider).
      ref.invalidate(sessionTimeoutMinutesProvider);
    } finally {
      if (mounted) setState(() => _sessionTimeoutLoading = false);
    }
  }

  Future<void> _updateAutoBackup(bool enabled) async {
    try {
      final repo = await ref.read(businessRepoProvider.future);
      await repo.saveSettings({'auto_backup_enabled': enabled ? '1' : '0'});
      ref.invalidate(appSettingsProvider);
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessProfileProvider);
    final profile = profileAsync.valueOrNull;
    final appSettingsAsync = ref.watch(appSettingsProvider);
    final appSettings = appSettingsAsync.valueOrNull;
    final rawSessionTimeout = int.tryParse(appSettings?['session_timeout_minutes'] ?? '') ??
        AppConstants.defaultInactivityTimeout.inMinutes;
    // Clamp so a corrupt/huge stored value can neither disable auto-lock nor
    // crash the DropdownButton assert (value must exist in items).
    final sessionTimeout = (rawSessionTimeout
            .clamp(AppConstants.minSessionTimeoutMinutes,
                AppConstants.maxSessionTimeoutMinutes))
        .toInt();
    final autoBackup = appSettings?['auto_backup_enabled'] == '1';
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentRoute: '/settings'),
      body: ListView(
        children: [
          // ── Business ──
          _SectionHeader(title: 'Business'),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Business Profile'),
            subtitle: Text(profile?.name ?? 'Edit business details and logo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/business'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_money),
            title: const Text('Financial Defaults'),
            subtitle: const Text('Currency, interest rates, loan settings, fees'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/business/financial_defaults'),
          ),

          const Divider(),

          // ── Security ──
          _SectionHeader(title: 'Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change PIN'),
            subtitle: const Text('Update your security PIN'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/security'),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Session Timeout'),
            subtitle: const Text('Auto-lock after inactivity'),
            trailing: _sessionTimeoutLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : DropdownButton<int>(
                    value: sessionTimeout,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 min')),
                      DropdownMenuItem(value: 3, child: Text('3 min')),
                      DropdownMenuItem(value: 5, child: Text('5 min')),
                      DropdownMenuItem(value: 10, child: Text('10 min')),
                      DropdownMenuItem(value: 15, child: Text('15 min')),
                      DropdownMenuItem(value: 30, child: Text('30 min')),
                      DropdownMenuItem(value: 120, child: Text('120 min')),
                    ],
                    onChanged: (v) {
                      if (v != null) _updateSessionTimeout(v);
                    },
                  ),
          ),

          const Divider(),

          // ── Appearance ──
          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: Icon(
              themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
            ),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18), label: Text('Light', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.auto_mode, size: 18), label: Text('Auto', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18), label: Text('Dark', style: TextStyle(fontSize: 12))),
              ],
              selected: {themeMode},
              onSelectionChanged: (selected) {
                ref.read(themeModeProvider.notifier).state = selected.first;
              },
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),

          const Divider(),

          // ── Cloud ──
          _SectionHeader(title: 'Cloud'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Cloud Sync'),
            subtitle: const Text('Optional backup to your Supabase cloud'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/cloud_sync'),
          ),

          const Divider(),

          // ── Data ──
          _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Create encrypted app backups or restore data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/backup'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('Auto-backup'),
            subtitle: const Text('Remind to backup daily'),
            value: autoBackup,
            onChanged: (v) => _updateAutoBackup(v),
          ),

          const Divider(),

          // ── Export ──
          _SectionHeader(title: 'Export'),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export Data'),
            subtitle: const Text('Export loans, customers, groups to Excel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/loans'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Statements'),
            subtitle: const Text('Loan, savings, and collection statements'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/statements/loan'),
          ),

          const Divider(),

          // ── Statements ──
          _SectionHeader(title: 'Statements'),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Loan Statement'),
            subtitle: const Text('Print or share a loan statement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/statements/loan'),
          ),
          ListTile(
            leading: const Icon(Icons.savings),
            title: const Text('Savings Statement'),
            subtitle: const Text('Print or share a savings statement'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/statements/savings'),
          ),
          ListTile(
            leading: const Icon(Icons.collections),
            title: const Text('Collection Statement'),
            subtitle: const Text('Print or share collection history'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/statements/collection'),
          ),

          const Divider(),

           // ── About ──
           _SectionHeader(title: 'About'),
           Padding(
             padding: const EdgeInsets.all(16.0),
             child: Center(
               child: Image.asset(
                 'attached_assets/full_horizontal_logo_1784971585520.png',
                 width: 220,
                 fit: BoxFit.contain,
               ),
             ),
           ),
           ListTile(
             leading: const Icon(Icons.info_outline),
             title: Text('About ${AppConstants.appName}'),
             subtitle: Text(
                 'Version ${AppConstants.appVersion} (${AppConstants.appBuildNumber})'),
           ),
           const ListTile(
             leading: Icon(Icons.badge),
             title: Text('App Creator'),
             subtitle: Text('AIGHEWI EGHOSA'),
           ),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
      ThemeMode.system => 'System default',
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
