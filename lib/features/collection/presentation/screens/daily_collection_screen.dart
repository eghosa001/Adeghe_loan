import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/debounced_text_field.dart';
import 'package:loantrack/core/widgets/keyboard_refreshable.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../groups/presentation/providers/group_providers.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../reports/services/export_manager.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../data/models/collection_row.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/data/models/payment_entity.dart';
import '../../../../core/di/providers.dart';
import '../providers/collection_provider.dart';
import '../widgets/collection_type_toggle.dart';

/// Daily Collection screen — daily loans only, viewable by date or date range
/// and by group. Weekly loans live in their own WeeklyCollectionScreen.
class DailyCollectionScreen extends ConsumerWidget {
  const DailyCollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionAsync = ref.watch(collectionListProvider);
    final selectedDate = ref.watch(collectionDateFilterProvider);
    final selectedGroup = ref.watch(collectionGroupFilterProvider);
    final groupsAsync = ref.watch(groupListProvider);
    final isRangeMode = ref.watch(collectionDateRangeModeProvider);
    final rangeStart = ref.watch(collectionRangeStartProvider);
    final rangeEnd = ref.watch(collectionRangeEndProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Collection'),
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
            onPressed: () => ref.invalidate(collectionListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Future Schedule',
            onPressed: () => context.push('/collections/future-schedule'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onSelected: (value) async {
              try {
                final result = await ref.read(collectionListProvider.future);
                final currencySymbol =
                    ref.read(currencySymbolProvider).valueOrNull ??
                    CurrencyUtils.defaultSymbol;
                if (value == 'excel') {
                  final file = await ExportManager.exportCollectionToExcel(
                    result,
                    selectedDate,
                  );
                  final opened = await OpenFilex.open(file.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          opened.type == ResultType.done
                              ? 'Excel opened: ${p.basename(file.path)}'
                              : 'Excel saved to downloads: ${p.basename(file.path)}',
                        ),
                      ),
                    );
                  }
                } else if (value == 'share_excel') {
                  await ExportManager.shareCollectionExcel(
                    result,
                    selectedDate,
                  );
                } else if (value == 'pdf') {
                  final file = await ExportManager.exportCollectionToPdf(
                    result,
                    selectedDate,
                    currencySymbol: currencySymbol,
                  );
                  final opened = await OpenFilex.open(file.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          opened.type == ResultType.done
                              ? 'PDF opened: ${p.basename(file.path)}'
                              : 'PDF saved: ${p.basename(file.path)}',
                        ),
                      ),
                    );
                  }
                } else if (value == 'share') {
                  await ExportManager.shareCollectionPdf(
                    result,
                    selectedDate,
                    currencySymbol: currencySymbol,
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'excel', child: Text('Export Excel')),
              const PopupMenuItem(
                value: 'share_excel',
                child: Text('Share Excel'),
              ),
              const PopupMenuItem(value: 'pdf', child: Text('Open PDF')),
              const PopupMenuItem(value: 'share', child: Text('Share PDF')),
            ],
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/collections'),
      body: Column(
        children: [
          const CollectionTypeToggle(isWeekly: false),
          // Date mode toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.date_range, size: 20),
                const SizedBox(width: 8),
                const Text('Date Range', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Switch(
                  value: isRangeMode,
                  onChanged: (v) {
                    ref.read(collectionDateRangeModeProvider.notifier).state =
                        v;
                  },
                ),
              ],
            ),
          ),
          // Date pickers — single or range
          if (!isRangeMode)
            _DatePickerTile(
              selectedDate: selectedDate,
              onDatePicked: (date) {
                ref.read(collectionDateFilterProvider.notifier).state = date;
              },
            )
          else
            _DateRangePickerTile(
              startDate: rangeStart,
              endDate: rangeEnd,
              onStartPicked: (date) {
                ref.read(collectionRangeStartProvider.notifier).state = date;
              },
              onEndPicked: (date) {
                ref.read(collectionRangeEndProvider.notifier).state = date;
              },
            ),
          groupsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (groups) {
              if (groups.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: selectedGroup == null,
                        onSelected: (_) =>
                            ref
                                    .read(
                                      collectionGroupFilterProvider.notifier,
                                    )
                                    .state =
                                null,
                      ),
                    ),
                    ...groups.map(
                      (g) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FilterChip(
                          label: Text(g.name),
                          selected: selectedGroup == g.id,
                          onSelected: (_) =>
                              ref
                                  .read(collectionGroupFilterProvider.notifier)
                                  .state = selectedGroup == g.id
                              ? null
                              : g.id,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DebouncedTextField(
              decoration: const InputDecoration(
                hintText: 'Search customer...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) =>
                  ref.read(collectionSearchQueryProvider.notifier).state = v,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('Sort by:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final sortBy = ref.watch(collectionSortByProvider);
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<CollectionSortBy>(
                          value: sortBy,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                              value: CollectionSortBy.name,
                              child: Text('Name'),
                            ),
                            DropdownMenuItem(
                              value: CollectionSortBy.amountDue,
                              child: Text('Amount Due'),
                            ),
                            DropdownMenuItem(
                              value: CollectionSortBy.amountPaid,
                              child: Text('Amount Paid'),
                            ),
                            DropdownMenuItem(
                              value: CollectionSortBy.outstanding,
                              child: Text('Outstanding'),
                            ),
                          ],
                          onChanged: (value) =>
                              ref
                                      .read(collectionSortByProvider.notifier)
                                      .state =
                                  value!,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: collectionAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text('No daily collections for this date.'),
                  );
                }
                return _buildSummaryAndList(context, ref, rows, isRangeMode);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndList(
    BuildContext context,
    WidgetRef ref,
    List<CollectionRow> rows, [
    bool isRangeMode = false,
  ]) {
    double totalDue = 0;
    double totalPaid = 0;
    for (final row in rows) {
      totalDue += row.amountDue;
      totalPaid += row.amountPaid;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(
                label: 'Total Due',
                value: CurrencyUtils.format(totalDue),
              ),
              _SummaryItem(
                label: 'Total Paid',
                value: CurrencyUtils.format(totalPaid),
              ),
              _SummaryItem(
                label: 'Remaining',
                value: CurrencyUtils.format(totalDue - totalPaid),
              ),
            ],
          ),
        ),
        Expanded(
          child: KeyboardRefreshable(
            onRefresh: () async => ref.invalidate(collectionListProvider),
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                // In range mode the payment cap is the first unpaid installment's
                // remaining amount (amountPaid already aggregates the whole range),
                // not that amount minus the range's already-paid total — that
                // double-subtraction would leave an artificially small cap and
                // push legitimate payment into savings.
                final installmentDue = isRangeMode
                    ? row.installmentAmount
                    : row.installmentAmount - row.amountPaid;
                return _CollectionRowTile(
                  row: row,
                  installmentDue: installmentDue > 0 ? installmentDue : 0,
                  onPaymentRecorded: () {
                    ref.invalidate(collectionListProvider);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CollectionRowTile extends ConsumerWidget {
  const _CollectionRowTile({
    required this.row,
    required this.installmentDue,
    required this.onPaymentRecorded,
  });

  final CollectionRow row;
  final double installmentDue;
  final VoidCallback onPaymentRecorded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(row.customerName),
      subtitle: Text(
        '${CurrencyUtils.format(row.amountPaid)} / ${CurrencyUtils.format(row.amountDue)}'
        '${row.groupName != null ? ' — ${row.groupName}' : ''}',
      ),
      trailing: row.isPaid
          ? const Icon(Icons.check_circle, color: Colors.green)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.bolt),
                  tooltip: 'Quick pay',
                  onPressed: () => _quickPay(context, ref),
                ),
                FilledButton.tonal(
                  onPressed: () => _openPayment(context),
                  child: const Text('Pay'),
                ),
              ],
            ),
      onTap: row.isPaid ? null : () => _openPayment(context),
    );
  }

  void _openPayment(BuildContext context) {
    if (row.loanId.isEmpty) return;
    context.push(
      '/loans/${row.loanId}/record-payment',
      extra: {
        'customerId': row.customerId,
        'currentBalance': row.outstandingBalance,
        'installmentDue': installmentDue > 0 ? installmentDue : null,
      },
    );
  }

  void _quickPay(BuildContext context, WidgetRef ref) {
    final amount = installmentDue > 0 ? installmentDue : row.outstandingBalance;
    if (amount <= 0) return;
    final currency =
        ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final amountCtrl = TextEditingController(text: amount.toStringAsFixed(0));
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
            Text(
              'Outstanding: ${CurrencyUtils.format(row.outstandingBalance)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (installmentDue > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Installment: ${CurrencyUtils.format(installmentDue)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: currency,
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Excess over installment goes to customer savings',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green),
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
              final entered = double.tryParse(amountCtrl.text) ?? 0;
              if (!entered.isFinite || entered <= 0) return;
              Navigator.pop(ctx);
              _recordQuickPayment(context, ref, entered, requestId);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordQuickPayment(
    BuildContext context,
    WidgetRef ref,
    double amount,
    String requestId,
  ) async {
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      final profileAsync = ref.read(businessProfileProvider);
      final collectorName = profileAsync.valueOrNull?.ownerName ?? 'Admin';
      await repo.createPayment(
        loanId: row.loanId,
        customerId: row.customerId,
        amount: amount,
        method: PaymentMethod.cash,
        collector: collectorName,
        installmentDue: installmentDue > 0 ? installmentDue : null,
        clientRequestId: requestId,
      );
      logAuditAction(
        ref,
        'UPDATE',
        'Payment ${CurrencyUtils.format(amount)} recorded for ${row.customerName} (loan ${row.loanId})',
      );
      ref.invalidate(collectionListProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(savingsBalanceProvider(row.customerId));
      ref.invalidate(savingsTransactionsProvider(row.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(customerProvider(row.customerId));
      ref.invalidate(reportSummaryProvider);
      ref.invalidate(customerListProvider);
      ref.invalidate(loanDetailsProvider(row.loanId));
      ref.invalidate(loanScheduleProvider(row.loanId));
      ref.invalidate(paymentsForLoanProvider(row.loanId));
      ref.invalidate(activeLoansForCustomerProvider(row.customerId));
      ref.invalidate(allLoansProvider);

      final effectiveInstallment = installmentDue > 0
          ? installmentDue
          : row.outstandingBalance;
      final surplus = amount - effectiveInstallment;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Paid ${CurrencyUtils.format(amount)} for ${row.customerName}'
              '${surplus > 0.01 ? '\n${CurrencyUtils.format(surplus)} credited to savings' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
      }
    }
  }
}

class _DatePickerTile extends StatelessWidget {
  const _DatePickerTile({
    required this.selectedDate,
    required this.onDatePicked,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDatePicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconButton(
        icon: const Icon(Icons.chevron_left),
        tooltip: 'Previous day',
        onPressed: () =>
            onDatePicked(selectedDate.subtract(const Duration(days: 1))),
      ),
      title: Text(AppDateUtils.formatDate(selectedDate)),
      subtitle: Text(AppDateUtils.formatRelative(selectedDate)),
      trailing: IconButton(
        icon: const Icon(Icons.chevron_right),
        tooltip: 'Next day',
        onPressed: () =>
            onDatePicked(selectedDate.add(const Duration(days: 1))),
      ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 5, now.month, now.day),
        );
        if (picked != null) onDatePicked(picked);
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DateRangePickerTile extends StatelessWidget {
  const _DateRangePickerTile({
    required this.startDate,
    required this.endDate,
    required this.onStartPicked,
    required this.onEndPicked,
  });

  final DateTime startDate;
  final DateTime endDate;
  final ValueChanged<DateTime> onStartPicked;
  final ValueChanged<DateTime> onEndPicked;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ListTile(
      leading: const Icon(Icons.date_range),
      title: Text(
        '${AppDateUtils.formatDate(startDate)} — ${AppDateUtils.formatDate(endDate)}',
      ),
      subtitle: Text('${endDate.difference(startDate).inDays + 1} days'),
      onTap: () async {
        // Cap the start at the current end date so a range can never be
        // inverted (picking a start after the end would leave start > end if
        // the end picker is then cancelled).
        final startUpperBound = endDate.isAfter(startDate)
            ? endDate
            : startDate;
        final lastAllowed = DateTime(now.year + 5, now.month, now.day);
        final pickedStart = await showDatePicker(
          context: context,
          initialDate: startDate,
          firstDate: DateTime(2020),
          lastDate: startUpperBound.isAfter(lastAllowed)
              ? lastAllowed
              : startUpperBound,
        );
        if (pickedStart != null) {
          onStartPicked(pickedStart);
          if (!context.mounted) return;
          final pickedEnd = await showDatePicker(
            context: context,
            initialDate: endDate.isAfter(pickedStart) ? endDate : pickedStart,
            firstDate: pickedStart,
            lastDate: DateTime(now.year + 5, now.month, now.day),
          );
          if (pickedEnd != null) onEndPicked(pickedEnd);
        }
      },
    );
  }
}
