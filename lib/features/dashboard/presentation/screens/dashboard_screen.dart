import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../data/models/dashboard_data.dart';
import '../providers/dashboard_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final notificationCount =
                  ref.watch(notificationProvider).valueOrNull?.length ?? 0;
              return IconButton(
                tooltip: 'Notifications',
                icon: Badge(
                  isLabelVisible: notificationCount > 0,
                  label: Text('$notificationCount',
                      style: const TextStyle(fontSize: 10)),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () => context.push('/notifications'),
              );
            },
          ),
        ],
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
              _MinimalStatCards(data: data),
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
                        onTap: () => context.push('/loans/${loan.id}'),
                      ),
                    )),
              ],
              if (data.recentLoans.isNotEmpty && data.recentPayments.isNotEmpty)
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
                        onTap: () => context.push('/collections'),
                      ),
                    )),
              ],
              if (data.recentSavingsTransactions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Recent Savings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                ...data.recentSavingsTransactions.take(5).map((txn) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: txn.isCredit
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          child: Icon(
                            txn.isCredit
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: txn.isCredit ? Colors.green : Colors.red,
                            size: 18,
                          ),
                        ),
                        title: Text(txn.customerName),
                        subtitle: Text(
                          '${txn.isCredit ? 'Deposit' : 'Withdrawal'} — ${txn.createdAt.split('T').first}',
                        ),
                        trailing: Text(
                          CurrencyUtils.format(txn.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: txn.isCredit ? Colors.green : Colors.red,
                          ),
                        ),
                        onTap: () => context.push('/customers/${txn.customerId}'),
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

class _MinimalStatCards extends StatelessWidget {
  const _MinimalStatCards({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Active Loans',
                value: data.activeLoans.toString(),
                icon: Icons.credit_card,
                color: Colors.green,
                onTap: () => context.go('/reports'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Outstanding',
                value: CurrencyUtils.format(data.outstandingBalance),
                icon: Icons.account_balance,
                color: Colors.red,
                onTap: () => context.go('/reports'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Collected',
                value: CurrencyUtils.format(data.totalCollected),
                icon: Icons.savings,
                color: Colors.teal,
                onTap: () => context.go('/reports'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Disbursed',
                value: CurrencyUtils.format(data.totalDisbursed),
                icon: Icons.trending_up,
                color: Colors.orange,
                onTap: () => context.go('/reports'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Savings',
                value: CurrencyUtils.format(data.totalSavingsBalance),
                icon: Icons.account_balance_wallet,
                color: Colors.indigo,
                onTap: () => context.go('/savings'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Customers',
                value: data.totalCustomers.toString(),
                icon: Icons.people,
                color: Colors.blue,
                onTap: () => context.push('/customers'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Groups',
                value: data.totalGroups.toString(),
                icon: Icons.group,
                color: Colors.purple,
                onTap: () => context.push('/groups'),
              ),
            ),
          ],
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
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.spaceAround,
      children: [
        _QuickAction(
          icon: Icons.person_add_outlined,
          label: 'Add\nCustomer',
          onTap: () => context.push('/customers/new'),
        ),
        _QuickAction(
          icon: Icons.request_quote_outlined,
          label: 'Create\nLoan',
          onTap: () => context.push('/customers'),
        ),
        _QuickAction(
          icon: Icons.payment,
          label: 'Record\nPayment',
          onTap: () => context.go('/collections'),
        ),
        _QuickAction(
          icon: Icons.savings_outlined,
          label: 'Savings\nDeposit',
          onTap: () => context.push('/savings'),
        ),
        _QuickAction(
          icon: Icons.logout,
          label: 'Savings\nWithdrawal',
          onTap: () => context.push('/savings'),
        ),
        _QuickAction(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Collection\nList',
          onTap: () => context.go('/collections'),
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
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor:
                  Theme.of(context).colorScheme.primaryContainer,
              child: Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
