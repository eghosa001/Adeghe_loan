import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/widgets/debounced_text_field.dart';
import '../../../../core/widgets/keyboard_refreshable.dart';
import '../../../reports/services/excel_export_service.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../providers/savings_providers.dart';

class SavingsOverviewScreen extends ConsumerWidget {
  const SavingsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(filteredAccountsWithNamesProvider);
    final currency =
        ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Savings'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (F5)',
            onPressed: () => ref.invalidate(filteredAccountsWithNamesProvider),
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export to Excel',
            onPressed: () async {
              final accounts = accountsAsync.valueOrNull;
              if (accounts == null || accounts.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No savings accounts to export'),
                  ),
                );
                return;
              }
              try {
                final headers = [
                  'Customer',
                  'Balance',
                  'Created Date',
                  'Status',
                ];
                final rows = accounts
                    .map(
                      (a) => [
                        a['customerName'] as String? ?? '',
                        CurrencyUtils.format(
                          (a['balance'] as num?)?.toDouble() ?? 0,
                          symbol: currency,
                        ),
                        (a['createdAt'] as String?)?.split('T').first ?? '-',
                        ((a['balance'] as num?)?.toDouble() ?? 0) > 0
                            ? 'Active'
                            : 'Empty',
                      ],
                    )
                    .toList();
                final file = await ExcelExportService.buildXlsx(
                  headers: headers,
                  rows: rows,
                  title: 'Savings Report',
                  sheetName: 'Savings',
                );
                await ExcelExportService.shareXlsx(file, 'Savings Report');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/savings'),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) {
          final query = ref.watch(savingsSearchQueryProvider);
          final totalBalance = accounts.fold<double>(
            0,
            (sum, a) => sum + ((a['balance'] as num?)?.toDouble() ?? 0),
          );
          final activeAccounts = accounts
              .where((a) => ((a['balance'] as num?)?.toDouble() ?? 0) > 0)
              .length;

          return KeyboardRefreshable(
            onRefresh: () async => ref.invalidate(filteredAccountsWithNamesProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SavingsSummaryCard(
                  totalBalance: totalBalance,
                  activeAccounts: activeAccounts,
                  accountCount: accounts.length,
                  currency: currency,
                ),
                const SizedBox(height: 20),
                DebouncedTextField(
                  initialValue: query,
                  decoration: const InputDecoration(
                    hintText: 'Search customer or phone...',
                    prefixIcon: Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      ref.read(savingsSearchQueryProvider.notifier).state = v,
                ),
                const SizedBox(height: 20),
                Text(
                  'Individual Accounts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (accounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      query.trim().isEmpty
                          ? 'No savings accounts yet. Savings are created automatically when overpayments are received.'
                          : 'No matching savings accounts found.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  ...accounts.map(
                    (account) => _AccountCard(
                      account: account,
                      currency: currency,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SavingsSummaryCard extends StatelessWidget {
  const _SavingsSummaryCard({
    required this.totalBalance,
    required this.activeAccounts,
    required this.accountCount,
    required this.currency,
  });

  final double totalBalance;
  final int activeAccounts;
  final int accountCount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.savings,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Total Savings Held',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyUtils.format(totalBalance, symbol: currency),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _OverviewPill(
                  label: '$activeAccounts active',
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                _OverviewPill(label: '$accountCount total', color: Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.currency});

  final Map<String, dynamic> account;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final name = account['customerName'] as String? ?? 'Unknown';
    final phone = account['phone'] as String? ?? '';
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final customerId = account['customerId'] as String? ?? '';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: balance > 0
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.1),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: balance > 0 ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(name),
        subtitle: Text(phone.isNotEmpty ? phone : customerId),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              CurrencyUtils.format(balance, symbol: currency),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: balance > 0 ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        onTap: () => context.push('/customers/$customerId'),
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  const _OverviewPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
