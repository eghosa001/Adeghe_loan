import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../data/models/dashboard_data.dart';
import '../providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
      ),
      drawer: const AppDrawer(currentRoute: '/dashboard'),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardDataProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _StatCardsRow(data: data),
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _QuickActionsSection(),
              const SizedBox(height: 24),
              if (data.recentLoans.isNotEmpty) ...[
                Text(
                  'Recent Loans',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                ...data.recentLoans.take(5).map((loan) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(loan.loanType.name.characters.first
                              .toUpperCase()),
                        ),
                        title: Text(CurrencyUtils.format(loan.amount)),
                        subtitle: Text(
                            'Outstanding: ${CurrencyUtils.format(loan.outstandingBalance)}'),
                        trailing: _StatusChip(status: loan.status.name),
                      ),
                    )),
              ],
              const SizedBox(height: 24),
              if (data.recentPayments.isNotEmpty) ...[
                Text(
                  'Recent Payments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                ...data.recentPayments.take(5).map((payment) => Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.payment),
                        ),
                        title: Text(CurrencyUtils.format(payment.amount)),
                        subtitle: Text(
                            '${payment.method.name} — ${payment.collector}'),
                        trailing: Text(
                          payment.paymentDate
                              .toIso8601String()
                              .split('T')
                              .first,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCardsRow extends StatelessWidget {
  const _StatCardsRow({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Customers',
                value: data.totalCustomers.toString(),
                icon: Icons.people_outline,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Active Loans',
                value: data.activeLoans.toString(),
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Disbursed',
                value: CurrencyUtils.format(data.totalDisbursed),
                icon: Icons.trending_up,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Collected',
                value: CurrencyUtils.format(data.totalCollected),
                icon: Icons.savings_outlined,
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatCard(
          label: 'Outstanding',
          value: CurrencyUtils.format(data.outstandingBalance),
          icon: Icons.receipt_long_outlined,
          color: Colors.red,
          fullWidth: true,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => Colors.green,
      'completed' => Colors.blue,
      'defaulted' => Colors.red,
      _ => Colors.grey,
    };
    return Chip(
      label: Text(status.toUpperCase(),
          style: const TextStyle(fontSize: 10, color: Colors.white)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _QuickAction(
          icon: Icons.person_add_outlined,
          label: 'New\nCustomer',
          onTap: () => GoRouter.of(context).go('/customers/new'),
        ),
        _QuickAction(
          icon: Icons.request_quote_outlined,
          label: 'New\nLoan',
          onTap: () => GoRouter.of(context).go('/customers'),
        ),
        _QuickAction(
          icon: Icons.payment,
          label: 'Record\nPayment',
          onTap: () => GoRouter.of(context).go('/customers'),
        ),
        _QuickAction(
          icon: Icons.receipt_long_outlined,
          label: 'Collection\nList',
          onTap: () => GoRouter.of(context).go('/dashboard'),
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
