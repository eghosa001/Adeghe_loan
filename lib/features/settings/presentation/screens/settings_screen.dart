import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:loantrack/core/constants/app_constants.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(title: 'Business'),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Business Profile'),
            subtitle: const Text('Edit business details and logo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => GoRouter.of(context).go('/settings/business'),
          ),
          ListTile(
            leading: const Icon(Icons.money),
            title: const Text('Financial Defaults'),
            subtitle: const Text('Default interest, fees and currency'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                GoRouter.of(context).go('/settings/business/financial_defaults'),
          ),
          const Divider(),
          _SectionHeader(title: 'Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Security Settings'),
            subtitle: const Text('Change PIN and manage biometrics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => GoRouter.of(context).go('/settings/security'),
          ),
          const Divider(),
          _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Create encrypted app backups or restore data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => GoRouter.of(context).go('/settings/backup'),
          ),
          const Divider(),
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About ${AppConstants.appName}'),
            subtitle: Text(
                'Version ${AppConstants.appVersion} (${AppConstants.appBuildNumber})'),
          ),
        ],
      ),
    );
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
