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
import '../../../reports/services/export_manager.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../data/models/weekly_collection_row.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../payments/data/models/payment_entity.dart';
import '../../../../core/di/providers.dart';
import '../providers/collection_provider.dart';
import '../widgets/bulk_collection.dart';
import '../widgets/collection_type_toggle.dart';

/// Weekly Collection screen — filter by date or date range to see which
/// weekly loans have payments due on the selected day(s). Works like Daily
/// Collection but for weekly loans whose installment due dates come from
/// the repayment schedule.
class WeeklyCollectionScreen extends ConsumerStatefulWidget {
  const WeeklyCollectionScreen({super.key});

  @override
  ConsumerState<WeeklyCollectionScreen> createState() =>
      _WeeklyCollectionScreenState();
}

class _WeeklyCollectionScreenState
    extends ConsumerState<WeeklyCollectionScreen> {
  bool _bulkMode = false;
  final Set<String> _selectedLoanIds = {};

  void _toggleBulkMode() {
    setState(() {
      _bulkMode = !_bulkMode;
      if (!_bulkMode) _selectedLoanIds.clear();
    });
  }

  void _toggleSelected(String loanId) {
    setState(() {
      if (!_selectedLoanIds.remove(loanId)) {
        _selectedLoanIds.add(loanId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final collectionAsync = ref.watch(weeklyCollectionListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Collection'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_bulkMode ? Icons.close : Icons.done_all),
            tooltip: _bulkMode ? 'Exit bulk collect' : 'Bulk collect',
            onPressed: _toggleBulkMode,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh (F5)',
            onPressed: () => ref.invalidate(weeklyCollectionListProvider),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onSelected: (value) async {
              try {
                final repo = await ref.read(
                  collectionRepositoryProvider.future,
                );
                final isRange = ref.read(weeklyCollectionDateRangeModeProvider);
                final rowsResult = isRange
                    ? await repo.getWeeklyCollectionByDateRange(
                        ref.read(weeklyCollectionRangeStartProvider),
                        ref.read(weeklyCollectionRangeEndProvider),
                      )
                    : await repo.getWeeklyCollectionByDate(
                        ref.read(weeklyCollectionDateFilterProvider),
                      );
                var rows = rowsResult.when(
                  success: (rows) => rows,
                  failure: (f) => throw f,
                );
                // Honor the search box: the export must match what the list
                // shows (the repository query itself has no search param, the
                // provider filters client-side).
                final query =
                    ref.read(weeklyCollectionSearchQueryProvider).trim();
                if (query.isNotEmpty) {
                  rows = rows
                      .where((r) => r.customerName
                          .toLowerCase()
                          .contains(query.toLowerCase()))
                      .toList();
                }
                // Use the selected date for the report title/filename
                final selectedDate = isRange
                    ? ref.read(weeklyCollectionRangeStartProvider)
                    : ref.read(weeklyCollectionDateFilterProvider);
                final currencySymbol =
                    ref.read(currencySymbolProvider).valueOrNull ??
                    CurrencyUtils.defaultSymbol;
                if (value == 'excel') {
                  final file =
                      await ExportManager.exportWeeklyCollectionToExcel(
                        rows,
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
                  await ExportManager.shareWeeklyCollectionExcel(
                    rows,
                    selectedDate,
                  );
                } else if (value == 'pdf') {
                  final file = await ExportManager.exportWeeklyCollectionToPdf(
                    rows,
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
                  await ExportManager.shareWeeklyCollectionPdf(
                    rows,
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
      drawer: const AppDrawer(currentRoute: '/collections/weekly'),
      bottomNavigationBar: _bulkMode
          ? _buildBulkBottomBar(collectionAsync.valueOrNull ?? const [])
          : null,
      body: collectionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => _buildCollectionView(context, rows),
      ),
    );
  }

  /// Builds the collection view. In normal mode the filters and summary bar
  /// stay pinned above a scrolling customer list; in bulk mode the whole upper
  /// area scrolls away with the customers so the maximum number of rows is
  /// visible while bulk-selecting. The bulk bottom bar stays fixed via
  /// [Scaffold.bottomNavigationBar].
  Widget _buildCollectionView(
    BuildContext context,
    List<WeeklyCollectionRow> rows,
  ) {
    final isRangeMode = ref.watch(weeklyCollectionDateRangeModeProvider);
    final selectedDate = ref.watch(weeklyCollectionDateFilterProvider);
    final rangeStart = ref.watch(weeklyCollectionRangeStartProvider);
    final rangeEnd = ref.watch(weeklyCollectionRangeEndProvider);

    Widget rowTile(WeeklyCollectionRow row) {
      return _WeeklyCollectionRowTile(
        row: row,
        onPaymentRecorded: () {
          ref.invalidate(weeklyCollectionListProvider);
        },
        selectMode: _bulkMode,
        selected: _selectedLoanIds.contains(row.loanId),
        onToggleSelected: () => _toggleSelected(row.loanId),
      );
    }

    final headers = <Widget>[
      const CollectionTypeToggle(isWeekly: true),
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
                ref.read(weeklyCollectionDateRangeModeProvider.notifier).state =
                    v;
              },
            ),
          ],
        ),
      ),
      // Date pickers — single or range
      if (!isRangeMode)
        _WeeklyDatePickerTile(
          selectedDate: selectedDate,
          onDatePicked: (date) {
            ref.read(weeklyCollectionDateFilterProvider.notifier).state = date;
          },
        )
      else
        _WeeklyDateRangePickerTile(
          startDate: rangeStart,
          endDate: rangeEnd,
          onStartPicked: (date) {
            ref.read(weeklyCollectionRangeStartProvider.notifier).state = date;
          },
          onEndPicked: (date) {
            ref.read(weeklyCollectionRangeEndProvider.notifier).state = date;
          },
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DebouncedTextField(
          // Re-seed from the query provider so the typed search survives a
          // hard reload (Refresh/F5/after recording a payment).
          initialValue: ref.watch(weeklyCollectionSearchQueryProvider),
          decoration: const InputDecoration(
            hintText: 'Search customer...',
            prefixIcon: Icon(Icons.search, size: 20),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              ref.read(weeklyCollectionSearchQueryProvider.notifier).state = v,
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
                  final sortBy = ref.watch(weeklyCollectionSortByProvider);
                  return DropdownButtonHideUnderline(
                    child: DropdownButton<CollectionSortBy>(
                      value: sortBy,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(
                          value: CollectionSortBy.disbursementDate,
                          child: Text('Disbursement Date'),
                        ),
                        DropdownMenuItem(
                          value: CollectionSortBy.paymentDay,
                          child: Text('Payment Day'),
                        ),
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
                          child: Text('Remaining'),
                        ),
                      ],
                      onChanged: (value) =>
                          ref
                                  .read(weeklyCollectionSortByProvider.notifier)
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
    ];

    // Normal mode: filters and the summary bar stay pinned; only the customer
    // list scrolls.
    if (!_bulkMode) {
      final sectionItems = _sectionItems(rows);
      return Column(
        children: [
          ...headers,
          if (rows.isNotEmpty) _buildSummaryBar(context, rows),
          Expanded(
            child: KeyboardRefreshable(
              onRefresh: () async =>
                  ref.invalidate(weeklyCollectionListProvider),
              child: rows.isEmpty
                  ? const Center(
                      child: Text('No weekly loans due in this period.'),
                    )
                  : ListView.builder(
                      itemCount: sectionItems.length,
                      itemBuilder: (context, index) {
                        final (day, row) = sectionItems[index];
                        if (row == null) {
                          return _PaymentDayHeader(day: day ?? '');
                        }
                        return Column(
                          children: [rowTile(row), const Divider(height: 1)],
                        );
                      },
                    ),
            ),
          ),
        ],
      );
    }

    // Bulk mode: the whole upper area scrolls away with the customers so the
    // maximum number of rows is visible while bulk-selecting.
    final sectionItems = _sectionItems(rows);
    final bodyItems = <Widget>[...headers];
    if (rows.isEmpty) {
      bodyItems.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: Text('No weekly loans due in this period.')),
        ),
      );
    } else {
      bodyItems.add(_buildSummaryBar(context, rows));
    }

    return KeyboardRefreshable(
      onRefresh: () async => ref.invalidate(weeklyCollectionListProvider),
      child: ListView.builder(
        itemCount: bodyItems.length + sectionItems.length,
        itemBuilder: (context, index) {
          if (index < bodyItems.length) return bodyItems[index];
          final (day, row) = sectionItems[index - bodyItems.length];
          if (row == null) {
            return _PaymentDayHeader(day: day ?? '');
          }
          return Column(children: [rowTile(row), const Divider(height: 1)]);
        },
      ),
    );
  }

  Widget _buildSummaryBar(
    BuildContext context,
    List<WeeklyCollectionRow> rows,
  ) {
    double totalExpected = 0;
    double totalPaid = 0;
    double totalCollectedThisPeriod = 0;
    int overdueCount = 0;
    for (final row in rows) {
      totalExpected += row.weeklyInstallment;
      totalPaid += row.amountPaid;
      totalCollectedThisPeriod += row.collectedThisPeriod;
      if (row.isOverdue) overdueCount++;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _SummaryItem(
              label: 'Expected This Week',
              value: CurrencyUtils.format(totalExpected),
            ),
          ),
          Expanded(
            child: _SummaryItem(
              label: 'Collected This Week',
              value: CurrencyUtils.format(totalCollectedThisPeriod),
            ),
          ),
          Expanded(
            child: _SummaryItem(
              label: 'Total Paid',
              value: CurrencyUtils.format(totalPaid),
            ),
          ),
          Expanded(
            child: _SummaryItem(
              label: 'Overdue',
              value: overdueCount.toString(),
              highlight: overdueCount > 0,
            ),
          ),
        ],
      ),
    );
  }

  /// Flattens the weekly rows into section markers: a day-header item is
  /// inserted whenever the recurring payment day changes, so collectors see
  /// every customer grouped under the day they repay. When sorted by Payment
  /// Day (the default) the sections run Monday → Sunday. Each item is a record
  /// `(day, row)` where a null row marks a header and a null day marks a row.
  List<(String?, WeeklyCollectionRow?)> _sectionItems(
    List<WeeklyCollectionRow> rows,
  ) {
    final items = <(String?, WeeklyCollectionRow?)>[];
    String? lastDay;
    for (final row in rows) {
      final day = row.paymentDay;
      if (day != lastDay) {
        items.add((day, null));
        lastDay = day;
      }
      items.add((null, row));
    }
    return items;
  }

  Widget _buildBulkBottomBar(List<WeeklyCollectionRow> rows) {
    final selectable =
        rows.where((r) => !r.isPaidForPeriod).toList();
    final selected = selectable
        .where((r) => _selectedLoanIds.contains(r.loanId))
        .toList();
    final total = selected.fold(
      0.0,
      (sum, row) => sum + _rowDefaultAmount(row),
    );
    final allSelected =
        selectable.isNotEmpty && selectable.length == _selectedLoanIds.length;
    return BulkCollectBottomBar(
      selectedCount: _selectedLoanIds.length,
      total: total,
      allSelected: allSelected,
      onSelectAll: () {
        setState(() {
          if (allSelected) {
            _selectedLoanIds.clear();
          } else {
            _selectedLoanIds
              ..clear()
              ..addAll(selectable.map((r) => r.loanId));
          }
        });
      },
      onCollect: () => _openBulkCollect(rows),
    );
  }

  double _rowDefaultAmount(WeeklyCollectionRow row) {
    return row.installmentDue > 0 ? row.installmentDue : row.outstandingBalance;
  }

  Future<void> _openBulkCollect(List<WeeklyCollectionRow> rows) async {
    final selected = rows
        .where(
          (r) => _selectedLoanIds.contains(r.loanId) && !r.isPaidForPeriod,
        )
        .toList();
    if (selected.isEmpty) return;
    final items = selected.map((row) {
      return BulkCollectItem(
        loanId: row.loanId,
        customerId: row.customerId,
        customerName: row.customerName,
        subtitle:
            'Week ${row.currentInstallmentNumber}'
            ' • ${row.currentInstallmentDueDate}',
        defaultAmount: _rowDefaultAmount(row),
        installmentDue: row.installmentDue,
        outstandingBalance: row.outstandingBalance,
      );
    }).toList();

    final currency =
        ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final draft = await showBulkCollectDialog(
      context,
      items,
      currencySymbol: currency,
    );
    if (draft == null || !mounted) return;

    setState(() {
      _bulkMode = false;
      _selectedLoanIds.clear();
    });
    final outcome = await recordBulkPayments(
      ref,
      items: draft.items,
      amounts: draft.amounts,
      method: draft.method,
      requestId: draft.requestId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(bulkCollectSummary(outcome, draft.total))),
    );
  }
}

/// A full-width banner showing the repayment day section for the rows below it.
class _PaymentDayHeader extends StatelessWidget {
  const _PaymentDayHeader({required this.day});

  final String day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = day.isEmpty ? 'No payment day' : day;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            size: 14,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyCollectionRowTile extends ConsumerWidget {
  const _WeeklyCollectionRowTile({
    required this.row,
    required this.onPaymentRecorded,
    this.selectMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  final WeeklyCollectionRow row;
  final VoidCallback onPaymentRecorded;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency =
        ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final theme = Theme.of(context);

    // Status indicator widget. A customer shows as "Paid" when the displayed
    // week's installment is fully paid OR the whole loan is completed — the row
    // represents the week the money pays for, so a late payment for an older
    // missed installment reads as "Paid" on that installment's week, never on
    // the week the money arrived.
    final paidForPeriod = row.isPaidForPeriod;
    Widget statusIndicator;
    String statusText;

    if (paidForPeriod) {
      statusIndicator = const Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 20,
      );
      statusText = 'Paid';
    } else if (row.isCurrentInstallmentPartial) {
      statusIndicator = const Icon(
        Icons.pending,
        color: Colors.orange,
        size: 20,
      );
      statusText = 'Partial';
    } else if (row.isOverdue) {
      statusIndicator = Icon(Icons.warning, color: Colors.red, size: 20);
      statusText = row.daysOverdue > 0 ? 'Overdue ${row.daysOverdue}d' : 'Overdue';
    } else {
      statusIndicator = const Icon(
        Icons.schedule,
        color: Colors.blue,
        size: 20,
      );
      statusText = 'Pending';
    }

    // The amount shown next to the status is what was actually collected in
    // the viewed period when paid (matches the green tick), otherwise the
    // current installment's due amount.
    final displayAmount = paidForPeriod && row.collectedThisPeriod > 0
        ? row.collectedThisPeriod
        : row.currentInstallmentAmount;

    return ListTile(
      leading: selectMode && !paidForPeriod
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelected?.call(),
            )
          : null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              row.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          statusIndicator,
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Week ${row.currentInstallmentNumber} • ${row.currentInstallmentDueDate}',
          ),
          Text(
            '${CurrencyUtils.format(displayAmount, symbol: currency)}  •  $statusText',
            style: TextStyle(
              color: paidForPeriod
                  ? Colors.green
                  : row.daysOverdue > 0
                  ? Colors.red
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: paidForPeriod
                  ? FontWeight.normal
                  : row.daysOverdue > 0
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
      isThreeLine: false,
      trailing: selectMode
          ? (paidForPeriod
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      Text(
                        'Paid',
                        style: TextStyle(color: Colors.green, fontSize: 10),
                      ),
                    ],
                  )
                : null)
          : paidForPeriod
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                Text(
                  'Paid',
                  style: TextStyle(color: Colors.green, fontSize: 10),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (row.isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'OVERDUE',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
      onTap: paidForPeriod
          ? null
          : selectMode
          ? onToggleSelected
          : () => _openPayment(context),
    );
  }

  void _openPayment(BuildContext context) {
    if (row.loanId.isEmpty) return;
    context.push(
      '/loans/${row.loanId}/record-payment',
      extra: {
        'customerId': row.customerId,
        'currentBalance': row.outstandingBalance,
        'installmentDue': row.installmentDue > 0 ? row.installmentDue : null,
      },
    );
  }

  void _quickPay(BuildContext context, WidgetRef ref) {
    final amount = row.installmentDue > 0
        ? row.installmentDue
        : row.outstandingBalance;
    if (amount <= 0) return;
    final currency =
        ref.read(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    final amountCtrl =
        TextEditingController(text: amount.toStringAsFixed(2));
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
            if (row.installmentDue > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Installment: ${CurrencyUtils.format(row.installmentDue)}',
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
        installmentDue: row.installmentDue > 0 ? row.installmentDue : null,
        clientRequestId: requestId,
      );
      logAuditAction(
        ref,
        'UPDATE',
        'Payment ${CurrencyUtils.format(amount)} recorded for ${row.customerName} (loan ${row.loanId})',
      );
      ref.invalidate(weeklyCollectionListProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(savingsBalanceProvider(row.customerId));
      ref.invalidate(savingsTransactionsProvider(row.customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(customerProvider(row.customerId));
      invalidateReportData(ref.invalidate);
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(customerListProvider);
      ref.invalidate(loanDetailsProvider(row.loanId));
      ref.invalidate(loanScheduleProvider(row.loanId));
      ref.invalidate(paymentsForLoanProvider(row.loanId));
      ref.invalidate(activeLoansForCustomerProvider(row.customerId));
      ref.invalidate(allLoansProvider);

      final effectiveInstallment = row.installmentDue > 0
          ? row.installmentDue
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

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.red : null,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Single date picker for weekly collection (mirrors daily collection's _DatePickerTile).
class _WeeklyDatePickerTile extends StatelessWidget {
  const _WeeklyDatePickerTile({
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

/// Date range picker for weekly collection (mirrors daily collection's _DateRangePickerTile).
class _WeeklyDateRangePickerTile extends StatelessWidget {
  const _WeeklyDateRangePickerTile({
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
