import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: const AppDrawer(currentRoute: '/settings'),
      body: ListView(
        children: [
          _SectionHeader(title: 'Business'),
          ListTile(
            leading: const Icon(Icons.business),
            title: const Text('Business Profile'),
            subtitle: const Text('Edit business details and logo'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/business'),
          ),
          ListTile(
            leading: const Icon(Icons.money),
            title: const Text('Financial Defaults'),
            subtitle: const Text('Default interest, fees and currency'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                context.push('/settings/business/financial_defaults'),
          ),
          const Divider(),
          _SectionHeader(title: 'Security'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Security Settings'),
            subtitle: const Text('Change PIN and manage biometrics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/security'),
          ),
          const Divider(),
          _SectionHeader(title: 'Data'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Create encrypted app backups or restore data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/backup'),
          ),
          const Divider(),
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
