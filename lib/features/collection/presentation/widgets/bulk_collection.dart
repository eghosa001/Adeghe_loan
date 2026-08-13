import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../payments/data/models/payment_entity.dart';
import '../../../payments/presentation/providers/payment_providers.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../savings/presentation/providers/savings_providers.dart';
import '../providers/collection_provider.dart';

/// A single customer/loan selected for batch collection. Amounts follow the
/// same conventions as the per-row quick-pay path: [defaultAmount] pre-fills
/// the dialog row (current installment remaining, falling back to the
/// outstanding balance), and [installmentDue] is the cap for the loan-applied
/// portion — any excess is credited to savings (money rule).
class BulkCollectItem {
  const BulkCollectItem({
    required this.loanId,
    required this.customerId,
    required this.customerName,
    required this.subtitle,
    required this.defaultAmount,
    required this.installmentDue,
    required this.outstandingBalance,
  });

  final String loanId;
  final String customerId;
  final String customerName;
  final String subtitle;
  final double defaultAmount;
  final double installmentDue;
  final double outstandingBalance;
}

/// Confirmed draft from the bulk-collection dialog — one editable amount per
/// selected item plus the shared payment method. [requestId] is minted once per
/// dialog session (not per submission) so a retried `recordBulkPayments` of the
/// SAME confirmed draft reuses the same per-item idempotency keys and can never
/// double-record a payment that already landed (F3).
class BulkCollectDraft {
  const BulkCollectDraft({
    required this.items,
    required this.amounts,
    required this.method,
    required this.requestId,
  });

  final List<BulkCollectItem> items;
  final List<double> amounts;
  final PaymentMethod method;
  final String requestId;

  double get total =>
      amounts.fold(0.0, (sum, amount) => sum + (amount.isFinite ? amount : 0));
}

/// Outcome of recording a batch: how many payments were written and which
/// customers failed (per-customer error strings).
class BulkCollectOutcome {
  const BulkCollectOutcome({required this.successCount, required this.failures});

  final int successCount;
  final List<String> failures;

  int get failedCount => failures.length;
}

/// Shows the batch-collection dialog. Returns a [BulkCollectDraft] when the
/// collector confirms, or null when cancelled. The draft carries a requestId
/// minted per dialog session (see [BulkCollectDraft.requestId]).
Future<BulkCollectDraft?> showBulkCollectDialog(
  BuildContext context,
  List<BulkCollectItem> items, {
  required String currencySymbol,
}) {
  final requestId = const Uuid().v4();
  return showDialog<BulkCollectDraft>(
    context: context,
    builder: (_) => _BulkCollectDialog(
      items: items,
      currencySymbol: currencySymbol,
      requestId: requestId,
    ),
  );
}

/// Records every draft payment via [PaymentRepository.createPayment] — a
/// stable idempotent `clientRequestId` per customer derived from the draft's
/// per-session [BulkCollectDraft.requestId] (`<requestId>-<index>`), the
/// selected method, the business owner as collector and the item's installment
/// cap — then invalidates the same provider families the per-row quick-pay path
/// touches (both collection lists, dashboard, savings, reports, future
/// schedule, loan details/schedule and payment history). Returns the
/// per-customer outcome.
Future<BulkCollectOutcome> recordBulkPayments(
  WidgetRef ref, {
  required List<BulkCollectItem> items,
  required List<double> amounts,
  required PaymentMethod method,
  required String requestId,
}) async {
  final failures = <String>[];
  var success = 0;
  try {
    final repo = await ref.read(paymentRepositoryProvider.future);
    final collectorName =
        ref.read(businessProfileProvider).valueOrNull?.ownerName ?? 'Admin';

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final amount = amounts[i];
      if (!amount.isFinite || amount <= 0) {
        failures.add('${item.customerName}: invalid amount');
        continue;
      }
      try {
        await repo.createPayment(
          loanId: item.loanId,
          customerId: item.customerId,
          amount: amount,
          method: method,
          collector: collectorName,
          installmentDue: item.installmentDue > 0 ? item.installmentDue : null,
          clientRequestId: '$requestId-$i',
        );
        logAuditAction(
          ref,
          'UPDATE',
          'Bulk payment ${CurrencyUtils.format(amount)} for '
              '${item.customerName} (loan ${item.loanId})',
        );
        success++;
      } catch (e) {
        failures.add('${item.customerName}: $e');
      }
    }
  } catch (e) {
    return BulkCollectOutcome(
      successCount: 0,
      failures: ['Unable to load payment service: $e'],
    );
  }

  ref.invalidate(collectionListProvider);
  ref.invalidate(weeklyCollectionListProvider);
  ref.invalidate(dashboardDataProvider);
  ref.invalidate(allSavingsAccountsProvider);
  ref.invalidate(allAccountsWithNamesProvider);
  invalidateReportData(ref.invalidate);
  ref.invalidate(futureScheduleProvider);
  ref.invalidate(customerListProvider);
  ref.invalidate(allLoansProvider);
  for (final item in items) {
    ref.invalidate(savingsBalanceProvider(item.customerId));
    ref.invalidate(savingsTransactionsProvider(item.customerId));
    ref.invalidate(customerProvider(item.customerId));
    ref.invalidate(loanDetailsProvider(item.loanId));
    ref.invalidate(loanScheduleProvider(item.loanId));
    ref.invalidate(paymentsForLoanProvider(item.loanId));
    ref.invalidate(activeLoansForCustomerProvider(item.customerId));
  }

  return BulkCollectOutcome(successCount: success, failures: failures);
}

/// SnackBar copy for a finished batch: success-only, mixed, or all-failed.
String bulkCollectSummary(BulkCollectOutcome outcome, double totalAmount) {
  if (outcome.failedCount == 0) {
    return 'Collected ${CurrencyUtils.format(totalAmount)} — '
        '${outcome.successCount} payment(s) recorded';
  }
  if (outcome.successCount == 0) {
    return 'No payments recorded. ${outcome.failures.join('; ')}';
  }
  return '${outcome.successCount} payment(s) recorded (${outcome.failedCount} '
      'failed: ${outcome.failures.join('; ')})';
}

/// The bottom action bar shown while a collection screen is in bulk mode:
/// selected count, running total, a Select all/None toggle and the Collect
/// button that opens the batch dialog.
class BulkCollectBottomBar extends StatelessWidget {
  const BulkCollectBottomBar({
    super.key,
    required this.selectedCount,
    required this.total,
    required this.allSelected,
    required this.onSelectAll,
    required this.onCollect,
  });

  final int selectedCount;
  final double total;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.done_all, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCount selected',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      CurrencyUtils.format(total),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onSelectAll,
                child: Text(allSelected ? 'None' : 'All'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: selectedCount == 0 ? null : onCollect,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Collect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkCollectDialog extends StatefulWidget {
  const _BulkCollectDialog({
    required this.items,
    required this.currencySymbol,
    required this.requestId,
  });

  final List<BulkCollectItem> items;
  final String currencySymbol;
  final String requestId;

  @override
  State<_BulkCollectDialog> createState() => _BulkCollectDialogState();
}

class _BulkCollectDialogState extends State<_BulkCollectDialog> {
  late final List<TextEditingController> _controllers;
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _controllers = widget.items
        .map((item) => TextEditingController(
              text: item.defaultAmount.toStringAsFixed(2),
            ))
        .toList();
    for (final controller in _controllers) {
      controller.addListener(_onAmountChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_onAmountChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _onAmountChanged() {
    // Keep the running total and the Confirm enable/disable state fresh.
    setState(() {});
  }

  bool get _allValid => _controllers.every((controller) {
        final v = CurrencyUtils.tryParsePositiveAmount(controller.text);
        return v != null;
      });

  double get _currentTotal {
    var total = 0.0;
    for (final controller in _controllers) {
      total += CurrencyUtils.tryParsePositiveAmount(controller.text) ?? 0;
    }
    return total;
  }

  void _confirm() {
    final amounts = _controllers
        .map((controller) =>
            CurrencyUtils.tryParsePositiveAmount(controller.text)!)
        .toList();
    Navigator.pop(
      context,
      BulkCollectDraft(
        items: widget.items,
        amounts: amounts,
        method: _method,
        requestId: widget.requestId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Collect ${widget.items.length} payment(s)'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                isDense: true,
              ),
              items: PaymentMethod.values
                  .map(
                    (method) => DropdownMenuItem(
                      value: method,
                      child: Text(method.name.toUpperCase()),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Excess over an installment goes to that customer\'s savings',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _buildItemRow(context, index),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  CurrencyUtils.format(_currentTotal,
                      symbol: widget.currencySymbol),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _allValid ? _confirm : null,
          child: const Text('Collect'),
        ),
      ],
    );
  }

  Widget _buildItemRow(BuildContext context, int index) {
    final item = widget.items[index];
    final controller = _controllers[index];
    final amount = CurrencyUtils.tryParsePositiveAmount(controller.text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.customerName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  item.subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                isDense: true,
                prefixText: widget.currencySymbol,
                border: const OutlineInputBorder(),
                errorText: amount == null ? 'Invalid' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
