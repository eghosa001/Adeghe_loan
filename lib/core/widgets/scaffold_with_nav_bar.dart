import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    required this.child,
    required this.currentPath,
    super.key,
  });

  final Widget child;
  final String currentPath;

  int get _currentIndex {
    if (currentPath.startsWith('/collections')) return 1;
    if (currentPath.startsWith('/reports')) return 2;
    if (currentPath.startsWith('/savings')) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
      case 1:
        context.go('/collections');
      case 2:
        context.go('/reports');
      case 3:
        context.go('/savings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => _onTap(context, index),
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primary.withValues(alpha: 0.12),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon:
                Icon(Icons.dashboard, color: colorScheme.primary),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet,
                color: colorScheme.primary),
            label: 'Collections',
          ),
          NavigationDestination(
            icon: const Icon(Icons.insert_chart_outlined),
            selectedIcon:
                Icon(Icons.insert_chart, color: colorScheme.primary),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: const Icon(Icons.savings_outlined),
            selectedIcon:
                Icon(Icons.savings, color: colorScheme.primary),
            label: 'Savings',
          ),
        ],
      ),
    );
  }
}
