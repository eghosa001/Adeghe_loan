import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_constants.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: colorScheme.primary,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'attached_assets/full_horizontal_logo_1784971585520.png',
                    width: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loan Management',
                    style: TextStyle(
                      color: colorScheme.onPrimary.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _MenuItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                    route: '/dashboard',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.people_outline,
                    label: 'Customers',
                    route: '/customers',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Collections',
                    route: '/collections',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.insert_chart_outlined,
                    label: 'Reports',
                    route: '/reports',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.calendar_today_outlined,
                    label: 'Holidays',
                    route: '/holidays',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.history_outlined,
                    label: 'Audit Log',
                    route: '/audit-log',
                    currentRoute: currentRoute,
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    route: '/settings',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.backup_outlined,
                    label: 'Backup & Restore',
                    route: '/settings/backup',
                    currentRoute: currentRoute,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentRoute == route ||
        (route != '/dashboard' && currentRoute.startsWith(route));

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        Navigator.of(context).pop();
        if (currentRoute != route) {
          GoRouter.of(context).go(route);
        }
      },
    );
  }
}
