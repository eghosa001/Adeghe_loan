import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/models/loan_entity.dart';
import '../../../reports/services/excel_export_service.dart';
import '../providers/loan_providers.dart';

class LoanListScreen extends ConsumerWidget {
  const LoanListScreen({super.key});

  static const _statusTabs = <String?>[null, 'active', 'completed', 'defaulted', 'cancelled'];
  static const _statusLabels = <String>['All', 'Active', 'Completed', 'Defaulted', 'Cancelled'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(allLoansProvider);
    final searchQuery = ref.watch(loanSearchQueryProvider);
    final statusFilter = ref.watch(loanStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export to Excel',
            onPressed: () async {
              final loans = loansAsync.valueOrNull;
              if (loans == null || loans.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No loans to export')),
                );
                return;
              }
              try {
                final headers = ['Loan ID', 'Customer ID', 'Amount',
                    'Outstanding', 'Rate', 'Status', 'Type', 'Date', 'Notes'];
                final rows = loans.map((l) => [
                  l.id,
                  l.customerId,
                  CurrencyUtils.format(l.amount),
                  CurrencyUtils.format(l.outstandingBalance),
                  '${l.interestRate}%',
                  l.status.name,
                  l.loanType.name,
                  l.loanDate.toIso8601String().split('T').first,
                  l.notes ?? '-',
                ]).toList();
                final file = await ExcelExportService.buildXlsx(
                  headers: headers,
                  rows: rows,
                  title: 'Loan Report',
                  sheetName: 'Loans',
                );
                await ExcelExportService.shareXlsx(file, 'Loan Report');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Export failed: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/loans'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              onChanged: (value) => ref.read(loanSearchQueryProvider.notifier).state = value,
              decoration: const InputDecoration(
                labelText: 'Search loans',
                hintText: 'Loan ID, customer name, or phone',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: List.generate(_statusTabs.length, (i) {
                final tabValue = _statusTabs[i];
                final isSelected = statusFilter == tabValue;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(_statusLabels[i]),
                    selected: isSelected,
                    onSelected: (_) {
                      ref.read(loanStatusFilterProvider.notifier).state =
                          isSelected ? null : tabValue;
                    },
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: loansAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (loans) {
                if (loans.isEmpty) {
                  final statusLabel = _statusLabels[
                      _statusTabs.indexOf(statusFilter)].toLowerCase();
                  return EmptyState(
                    icon: Icons.monetization_on_outlined,
                    title: 'No ${statusFilter != null ? statusLabel : ''} loans found',
                    subtitle: searchQuery.isNotEmpty
                        ? 'Try a different search term.'
                        : 'Loans will appear here once created.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(allLoansProvider),
                  child: ListView.separated(
                    itemCount: loans.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final loan = loans[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(loan.status),
                          child: Text(
                            loan.loanType == LoanType.daily ? 'D' : 'W',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        title: Text(
                          _getCustomerName(loan) ?? loan.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${CurrencyUtils.format(loan.amount)} • ${loan.status.name.toUpperCase()}'
                          ' • ${loan.loanType.name}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(CurrencyUtils.format(loan.outstandingBalance),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('outstanding',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        onTap: () => context.push('/loans/${loan.id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(LoanStatus status) {
    return switch (status) {
      LoanStatus.active => Colors.green,
      LoanStatus.completed => Colors.blue,
      LoanStatus.defaulted => Colors.red,
      LoanStatus.pending => Colors.orange,
      LoanStatus.cancelled => Colors.grey,
    };
  }

  String? _getCustomerName(Loan loan) {
    return loan.customerName ?? loan.id;
  }
}
