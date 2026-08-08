import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/data/models/payment_entity.dart';
import '../../data/models/collection_row.dart';
import '../providers/collection_provider.dart';

class FutureScheduleScreen extends ConsumerWidget {
  const FutureScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(futureScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Future Collection Schedule'),
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_available, size: 80,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No upcoming collections in the next 30 days.',
                      style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            );
          }

          final grouped = <String, List<CollectionRow>>{};
          for (final row in rows) {
            final date = row.dueDate ?? '';
            grouped.putIfAbsent(date, () => []).add(row);
          }
          final sortedDates = grouped.keys.toList()..sort();

          double grandTotal = 0;
          for (final row in rows) {
            grandTotal += (row.amountDue - row.amountPaid).clamp(0, double.infinity);
          }

          // Flatten day headers + rows so the lazy builder only materializes
          // the visible items instead of eagerly building every day's full
          // row set inside a single card.
          final items = <(String?, CollectionRow?)>[];
          for (final date in sortedDates) {
            items.add((date, null));
            items.addAll(grouped[date]!.map((r) => (null, r)));
          }

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      label: 'Upcoming Days',
                      value: '${sortedDates.length}',
                    ),
                    _StatItem(
                      label: 'Total Installments',
                      value: '${rows.length}',
                    ),
                    _StatItem(
                      label: 'Total Expected',
                      value: CurrencyUtils.format(grandTotal),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(futureScheduleProvider),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final (date, row) = items[index];
                      if (row == null) {
                        return _buildDayHeaderCard(context, date!, grouped[date]!);
                      }
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 2),
                        child: ListTile(
                          dense: true,
                          title: Text(row.customerName),
                          subtitle: Text(
                              '${row.loanType}${row.groupName != null ? ' — ${row.groupName}' : ''}'
                              '${row.amountPaid > 0 ? '  ·  ${CurrencyUtils.format(row.amountPaid)} already paid' : ''}'),
                          trailing: Text(
                            CurrencyUtils.format(
                                (row.amountDue - row.amountPaid)
                                    .clamp(0, double.infinity)),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
                          ),
                          onTap: () {
                            _quickPay(context, ref, row);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _quickPay(BuildContext context, WidgetRef ref, CollectionRow row) {
    final remaining = row.amountDue - row.amountPaid;
    if (remaining <= 0) return;
    final currency =
        ref.read(currencySymbolProvider).valueOrNull ?? CurrencyUtils.defaultSymbol;
    final ctrl = TextEditingController(text: remaining.toStringAsFixed(0));
    // Stable id for THIS payment action: reused if the confirm is retried so a
    // timeout/retry can never double-record the same logical payment (F3).
    final requestId = const Uuid().v4();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pay ${row.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount due: ${CurrencyUtils.format(row.amountDue)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (row.amountPaid > 0)
              Text('Already paid: ${CurrencyUtils.format(row.amountPaid)}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: currency,
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(ctrl.text) ?? 0;
              if (!amount.isFinite || amount <= 0) return;
              Navigator.pop(ctx);
              _doQuickPay(context, ref, row, amount, requestId);
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  Future<void> _doQuickPay(BuildContext context, WidgetRef ref,
      CollectionRow row, double amount, String requestId) async {
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      final profileAsync = ref.read(businessProfileProvider);
      final collector = profileAsync.valueOrNull?.ownerName ?? 'Admin';
      await repo.createPayment(
        loanId: row.loanId,
        customerId: row.customerId,
        amount: amount,
        method: PaymentMethod.cash,
        collector: collector,
        installmentDue: row.amountDue > 0 ? row.amountDue : null,
        clientRequestId: requestId,
      );
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(collectionListProvider);
      ref.invalidate(weeklyCollectionListProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(savingsBalanceProvider(row.customerId));
      ref.invalidate(savingsTransactionsProvider(row.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(customerProvider(row.customerId));
      ref.invalidate(customerListProvider);
      ref.invalidate(reportSummaryProvider);
      ref.invalidate(loanDetailsProvider(row.loanId));
      ref.invalidate(loanScheduleProvider(row.loanId));
      ref.invalidate(paymentsForLoanProvider(row.loanId));
      ref.invalidate(activeLoansForCustomerProvider(row.customerId));
      ref.invalidate(allLoansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paid ${CurrencyUtils.format(amount)} for ${row.customerName}'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e')),
        );
      }
    }
  }

  Widget _buildDayHeaderCard(
      BuildContext context, String date, List<CollectionRow> dayRows) {
    final dayTotal = dayRows.fold<double>(0, (s, r) =>
        s + (r.amountDue - r.amountPaid).clamp(0, double.infinity));
    final parsed = DateTime.tryParse(date);
    final label = parsed != null
        ? '${AppDateUtils.formatDate(parsed)}  ·  ${DateFormat('EEEE').format(parsed)}'
        : date;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              CurrencyUtils.format(dayTotal),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
