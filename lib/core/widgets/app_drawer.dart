import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.accentGradient,
                    ),
                    child: Center(
                      child: Text(
                        'A',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Adeghe Professional Services',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Professional Services Management',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _MenuItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Dashboard',
                    route: '/dashboard',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.people_rounded,
                    label: 'Customers',
                    route: '/customers',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.group_rounded,
                    label: 'Customer Groups',
                    route: '/groups',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.monetization_on_rounded,
                    label: 'Loans',
                    route: '/loans',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Daily Collection',
                    route: '/collections',
                    currentRoute: currentRoute,
                    highlightExact: true,
                  ),
                  _MenuItem(
                    icon: Icons.calendar_view_week_rounded,
                    label: 'Weekly Collection',
                    route: '/collections/weekly',
                    currentRoute: currentRoute,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(),
                  ),
                  _MenuItem(
                    icon: Icons.insert_chart_rounded,
                    label: 'Reports',
                    route: '/reports',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.savings_rounded,
                    label: 'Savings',
                    route: '/savings',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.calendar_month_rounded,
                    label: 'Holidays',
                    route: '/holidays',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.notifications_rounded,
                    label: 'Notifications',
                    route: '/notifications',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.search_rounded,
                    label: 'Global Search',
                    route: '/search',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.history_rounded,
                    label: 'Audit Log',
                    route: '/audit-log',
                    currentRoute: currentRoute,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(),
                  ),
                  _MenuItem(
                    icon: Icons.settings_rounded,
                    label: 'Settings',
                    route: '/settings',
                    currentRoute: currentRoute,
                  ),
                  _MenuItem(
                    icon: Icons.cloud_upload_rounded,
                    label: 'Backup & Restore',
                    route: '/settings/backup',
                    currentRoute: currentRoute,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Created by AIGHEWI EGHOSA',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${AppConstants.appVersion} (Build ${AppConstants.appBuildNumber})',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
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

  /// When true the item highlights only on an exact route match. Used for
  /// `/collections` (Daily) so navigating to `/collections/weekly` does not
  /// highlight the Daily item too.
  final bool highlightExact;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
    this.highlightExact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = highlightExact
        ? currentRoute == route
        : currentRoute == route ||
            (route != '/dashboard' && currentRoute.startsWith(route));
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).pop();
            if (currentRoute != route) {
              const shellPrefixes = ['/dashboard', '/collections', '/reports', '/savings'];
              final isShellRoute =
                  shellPrefixes.any((s) => route == s || route.startsWith('$s/'));
              if (isShellRoute) {
                GoRouter.of(context).go(route);
              } else {
                GoRouter.of(context).push(route);
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accentColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
