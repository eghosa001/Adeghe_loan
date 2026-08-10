import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../data/dashboard_repository.dart';
import '../../data/models/dashboard_data.dart';
import '../providers/dashboard_provider.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../business/presentation/providers/business_providers.dart';

/// State notifier for managing dashboard period selection
class DashboardPeriodNotifier extends StateNotifier<DashboardPeriod> {
  DashboardPeriodNotifier() : super(DashboardPeriod.today);

  void setPeriod(DashboardPeriod period) => state = period;
  void reset() => state = DashboardPeriod.today;
}

final dashboardPeriodProvider = StateNotifierProvider<DashboardPeriodNotifier, DashboardPeriod>(
  (ref) => DashboardPeriodNotifier(),
);

/// Dashboard data provider that accepts period parameter
final dashboardDataProviderWithPeriod = FutureProvider.family<DashboardData, DashboardPeriod>((ref, period) async {
  final dbService = await ref.watch(databaseServiceProvider.future);
  final repo = DashboardRepository(dbService);
  final result = await repo.getDashboardData(period: period);
  return result.when(
    success: (data) => data,
    failure: (f) => throw f,
  );
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final selectedPeriod = ref.watch(dashboardPeriodProvider);
    final dashboardAsync = ref.watch(dashboardDataProviderWithPeriod(selectedPeriod));
    final currency =
        ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          // Period selector dropdown
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButton<DashboardPeriod>(
              value: selectedPeriod,
              underline: const SizedBox(),
              icon: const Icon(Icons.calendar_today, size: 18),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              items: [
                DropdownMenuItem(
                  value: DashboardPeriod.today,
                  child: Text('Today'),
                ),
                DropdownMenuItem(
                  value: DashboardPeriod.yesterday,
                  child: Text('Yesterday'),
                ),
                DropdownMenuItem(
                  value: DashboardPeriod.thisWeek,
                  child: Text('This Week'),
                ),
                DropdownMenuItem(
                  value: DashboardPeriod.thisMonth,
                  child: Text('This Month'),
                ),
                DropdownMenuItem(
                  value: DashboardPeriod.lastMonth,
                  child: Text('Last Month'),
                ),
              ],
              onChanged: (period) {
                if (period != null) {
                  ref.read(dashboardPeriodProvider.notifier).setPeriod(period);
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Refresh (F5)',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(dashboardDataProviderWithPeriod(selectedPeriod)),
          ),
          Consumer(
            builder: (context, ref, _) {
              final notificationCount =
                  ref.watch(notificationProvider).valueOrNull?.length ?? 0;
              return IconButton(
                tooltip: 'Notifications',
                icon: Badge(
                  isLabelVisible: notificationCount > 0,
                  label: Text(
                    '$notificationCount',
                    style: const TextStyle(fontSize: 10),
                  ),
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
        data: (data) => KeyboardRefreshable(
          onRefresh: () async {
            ref.invalidate(dashboardDataProviderWithPeriod(selectedPeriod));
          },
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _FinancialSummaryCards(data: data, currency: currency),
              const SizedBox(height: 24),
              _TodaysCollectionSection(data: data, currency: currency),
              const SizedBox(height: 24),
              _LoanPortfolioSection(data: data),
              const SizedBox(height: 24),
              _OverdueRiskSection(data: data, currency: currency),
              const SizedBox(height: 24),
              _IncomeProfitSection(data: data, currency: currency),
              const SizedBox(height: 24),
              _CustomerStatsSection(data: data),
              const SizedBox(height: 24),
              _SavingsSection(data: data, currency: currency),
              const SizedBox(height: 24),
              if (data.recentLoans.isNotEmpty) ...[
                Text(
                  'Recent Loans',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.recentLoans
                    .take(5)
                    .map(
                      (loan) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              loan.loanType.name.characters.first.toUpperCase(),
                            ),
                          ),
                          title: Text(
                            CurrencyUtils.format(loan.amount, symbol: currency),
                          ),
                          subtitle: Text(
                            'Outstanding: ${CurrencyUtils.format(loan.outstandingBalance, symbol: currency)}',
                          ),
                          trailing: _StatusChip(status: loan.status.name),
                          onTap: () => context.push('/loans/${loan.id}'),
                        ),
                      ),
                    ),
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
                ...data.recentPayments
                    .take(5)
                    .map(
                      (payment) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.payment),
                          ),
                          title: Text(
                            CurrencyUtils.format(
                              payment.amount,
                              symbol: currency,
                            ),
                          ),
                          subtitle: Text(
                            '${payment.method.name} — ${payment.collector}',
                          ),
                          trailing: Text(
                            payment.paymentDate
                                .toIso8601String()
                                .split('T')
                                .first,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: () => context.push('/collections'),
                        ),
                      ),
                    ),
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
                ...data.recentSavingsTransactions
                    .take(5)
                    .map(
                      (txn) => Card(
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
                            '${txn.typeLabel} — ${txn.createdAt.split('T').first}',
                          ),
                          trailing: Text(
                            CurrencyUtils.format(txn.amount, symbol: currency),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: txn.isCredit ? Colors.green : Colors.red,
                            ),
                          ),
                          onTap: () =>
                              context.push('/customers/${txn.customerId}'),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 24),
              _QuickActionsSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinancialSummaryCards extends StatelessWidget {
  const _FinancialSummaryCards({required this.data, required this.currency});
  final DashboardData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FINANCIAL SUMMARY',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              label: 'Total Disbursed',
              value: CurrencyUtils.format(data.periodDisbursed, symbol: currency),
              icon: Icons.money_off,
              color: Colors.orange,
            ),
            _StatCard(
              label: 'Total Collected',
              value: CurrencyUtils.format(data.periodCollected, symbol: currency),
              icon: Icons.savings,
              color: Colors.teal,
            ),
            _StatCard(
              label: 'Total Expected',
              value: CurrencyUtils.format(data.totalExpected, symbol: currency),
              icon: Icons.pending_actions,
              color: Colors.blue,
            ),
            _StatCard(
              label: 'Outstanding Balance',
              value: CurrencyUtils.format(data.outstandingBalance, symbol: currency),
              icon: Icons.account_balance,
              color: Colors.red,
            ),
            _StatCard(
              label: 'Overdue',
              value: CurrencyUtils.format(data.totalOverdue, symbol: currency),
              icon: Icons.warning,
              color: Colors.deepOrange,
            ),
            _StatCard(
              label: 'Savings',
              value: CurrencyUtils.format(data.totalSavingsBalance, symbol: currency),
              icon: Icons.account_balance_wallet,
              color: Colors.indigo,
            ),
          ],
        ),
      ],
    );
  }
}

class _TodaysCollectionSection extends StatelessWidget {
  const _TodaysCollectionSection({required this.data, required this.currency});
  final DashboardData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "TODAY'S COLLECTION",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => context.go('/collections'),
                      icon: const Icon(Icons.today, size: 16),
                      label: const Text('Daily'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.go('/collections/weekly'),
                      icon: const Icon(Icons.calendar_view_week, size: 16),
                      label: const Text('Weekly'),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _CollectionMetric(
                    label: 'Expected Today',
                    value: CurrencyUtils.format(data.todayExpected, symbol: currency),
                  ),
                ),
                Expanded(
                  child: _CollectionMetric(
                    label: 'Collected Today',
                    value: CurrencyUtils.format(data.todayCollected, symbol: currency),
                    isPositive: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CollectionMetric(
                    label: 'Remaining',
                    value: CurrencyUtils.format(
                      (data.todayExpected - data.todayCollected).clamp(0.0, double.infinity),
                      symbol: currency,
                    ),
                  ),
                ),
                Expanded(
                  child: _CollectionMetric(
                    label: 'Collection Rate',
                    value: '${data.collectionRate.toStringAsFixed(0)}%',
                    isPercentage: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CustomerCountChip(
                  label: 'Due Today',
                  count: data.todayDueCustomers,
                  color: Colors.blue,
                ),
                _CustomerCountChip(
                  label: 'Paid',
                  count: data.todayPaidCustomers,
                  color: Colors.green,
                ),
                _CustomerCountChip(
                  label: 'Pending',
                  count: data.todayPendingCustomers,
                  color: Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionMetric extends StatelessWidget {
  const _CollectionMetric({
    required this.label,
    required this.value,
    this.isPositive = false,
    this.isPercentage = false,
  });
  final String label;
  final String value;
  final bool isPositive;
  final bool isPercentage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isPositive ? Colors.green : null,
          ),
        ),
      ],
    );
  }
}

class _CustomerCountChip extends StatelessWidget {
  const _CustomerCountChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Chip(
          avatar: CircleAvatar(
            radius: 10,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(Icons.person, size: 14, color: color),
          ),
          label: Text('$count', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: color.withValues(alpha: 0.1),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LoanPortfolioSection extends StatelessWidget {
  const _LoanPortfolioSection({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LOAN PORTFOLIO',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _PortfolioItem(
                    label: 'Active Loans',
                    value: data.activeLoans.toString(),
                    icon: Icons.credit_card,
                  ),
                ),
                Expanded(
                  child: _PortfolioItem(
                    label: 'Completed',
                    value: data.completedLoans.toString(),
                    icon: Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PortfolioItem(
                    label: 'Daily Loans',
                    value: data.dailyActiveLoans.toString(),
                    icon: Icons.today,
                  ),
                ),
                Expanded(
                  child: _PortfolioItem(
                    label: 'Weekly Loans',
                    value: data.weeklyActiveLoans.toString(),
                    icon: Icons.calendar_view_week,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PortfolioItem extends StatelessWidget {
  const _PortfolioItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverdueRiskSection extends StatelessWidget {
  const _OverdueRiskSection({required this.data, required this.currency});
  final DashboardData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OVERDUE / RISK',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Overdue',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        CurrencyUtils.format(data.totalOverdue, symbol: currency),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _OverdueBucket(
                    label: '1-7 Days',
                    value: CurrencyUtils.format(data.overdue1to7Days, symbol: currency),
                  ),
                ),
                Expanded(
                  child: _OverdueBucket(
                    label: '8-30 Days',
                    value: CurrencyUtils.format(data.overdue8to30Days, symbol: currency),
                  ),
                ),
                Expanded(
                  child: _OverdueBucket(
                    label: '31+ Days',
                    value: CurrencyUtils.format(data.overdue31PlusDays, symbol: currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RiskChip(label: 'PAR 1+', value: '${data.par1Plus.toStringAsFixed(1)}%'),
                _RiskChip(label: 'PAR 7+', value: '${data.par7Plus.toStringAsFixed(1)}%'),
                _RiskChip(label: 'PAR 30+', value: '${data.par30Plus.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${data.overdueLoansCount} loans • ${data.overdueCustomersCount} customers overdue',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverdueBucket extends StatelessWidget {
  const _OverdueBucket({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _RiskChip extends StatelessWidget {
  const _RiskChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.deepOrange.withValues(alpha: 0.1),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IncomeProfitSection extends StatelessWidget {
  const _IncomeProfitSection({required this.data, required this.currency});
  final DashboardData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INCOME / PROFIT',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            _IncomeRow(
              label: 'Interest Earned',
              value: CurrencyUtils.format(data.totalInterestEarned, symbol: currency),
            ),
            _IncomeRow(
              label: 'Other Income',
              value: CurrencyUtils.format(data.totalFeesEarned, symbol: currency),
            ),
            const Divider(),
            _IncomeRow(
              label: 'Total Income',
              value: CurrencyUtils.format(
                data.totalInterestEarned + data.totalFeesEarned,
                symbol: currency,
              ),
              isBold: true,
            ),
            _IncomeRow(
              label: 'Expenses',
              value: '- ${CurrencyUtils.format(data.totalExpenses, symbol: currency)}',
              isNegative: true,
            ),
            const Divider(),
            _IncomeRow(
              label: 'Net Profit',
              value: CurrencyUtils.format(data.netProfit, symbol: currency),
              isBold: true,
              isPositive: data.netProfit >= 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomeRow extends StatelessWidget {
  const _IncomeRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.isNegative = false,
    this.isPositive = false,
  });
  final String label;
  final String value;
  final bool isBold;
  final bool isNegative;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: isBold ? FontWeight.bold : null,
              color: isNegative
                  ? Colors.red
                  : isPositive
                      ? Colors.green
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerStatsSection extends StatelessWidget {
  const _CustomerStatsSection({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CUSTOMERS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _CustomerStat(
                    label: 'Total Customers',
                    value: data.totalCustomers.toString(),
                    icon: Icons.people,
                  ),
                ),
                Expanded(
                  child: _CustomerStat(
                    label: 'Active Borrowers',
                    value: data.activeLoans.toString(),
                    icon: Icons.credit_card,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'NEW CUSTOMERS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NewCustomerStat(
                    label: 'Today',
                    count: data.newCustomersToday,
                  ),
                ),
                Expanded(
                  child: _NewCustomerStat(
                    label: 'This Week',
                    count: data.newCustomersThisWeek,
                  ),
                ),
                Expanded(
                  child: _NewCustomerStat(
                    label: 'This Month',
                    count: data.newCustomersThisMonth,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerStat extends StatelessWidget {
  const _CustomerStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NewCustomerStat extends StatelessWidget {
  const _NewCustomerStat({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '+$count',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SavingsSection extends StatelessWidget {
  const _SavingsSection({required this.data, required this.currency});
  final DashboardData data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SAVINGS',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _SavingsStat(
                    label: 'Total Balance',
                    value: CurrencyUtils.format(data.totalSavingsBalance, symbol: currency),
                    icon: Icons.account_balance_wallet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SavingsDetail(
                    label: 'Deposits (Month)',
                    value: CurrencyUtils.format(data.savingsDepositsThisMonth, symbol: currency),
                    isPositive: true,
                  ),
                ),
                Expanded(
                  child: _SavingsDetail(
                    label: 'Withdrawals (Month)',
                    value: '- ${CurrencyUtils.format(data.savingsWithdrawalsThisMonth, symbol: currency)}',
                    isNegative: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Net: ${CurrencyUtils.format(
                      data.savingsDepositsThisMonth - data.savingsWithdrawalsThisMonth,
                      symbol: currency,
                    )}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SavingsStat extends StatelessWidget {
  const _SavingsStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.indigo.withValues(alpha: 0.1),
          child: Icon(icon, color: Colors.indigo, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SavingsDetail extends StatelessWidget {
  const _SavingsDetail({
    required this.label,
    required this.value,
    this.isPositive = false,
    this.isNegative = false,
  });
  final String label;
  final String value;
  final bool isPositive;
  final bool isNegative;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isPositive ? Colors.green : isNegative ? Colors.red : null,
          ),
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
              child: Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
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
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
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
          label: 'Savings\nAccount',
          onTap: () => context.push('/savings'),
        ),
        _QuickAction(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Daily\nCollection',
          onTap: () => context.go('/collections'),
        ),
        _QuickAction(
          icon: Icons.calendar_view_week_outlined,
          label: 'Weekly\nCollection',
          onTap: () => context.go('/collections/weekly'),
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
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
