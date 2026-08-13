import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:loantrack/core/widgets/empty_state.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';
import 'package:loantrack/core/utils/currency_utils.dart';

import '../../data/models/payment_entity.dart';
import '../providers/payment_providers.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../savings/presentation/providers/savings_providers.dart';


class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({
    super.key,
    required this.loanId,
    required this.customerId,
  });

  final String loanId;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(paymentsForLoanProvider(loanId));

    return Scaffold(
      appBar: AppBar(title: const Text('Payment History')),
      body: paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (payments) {
          if (payments.isEmpty) return const _EmptyState();
          return KeyboardScrollable(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: payments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _PaymentCard(
                    payment: payments[index],
                    ref: ref,
                    loanId: loanId,
                    customerId: customerId,
                  ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.receipt_long,
      title: 'No payments recorded yet',
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.ref,
    required this.loanId,
    required this.customerId,
  });

  final Payment payment;
  final WidgetRef ref;
  final String loanId;
  final String customerId;

  String get _currency =>
      ref.read(currencySymbolProvider).valueOrNull ??
      CurrencyUtils.defaultSymbol;

  String _formatDate(DateTime d) {
    // `payment_date` is a date-only string (yyyy-MM-dd), so its parsed DateTime
    // carries a midnight time — rendering a fake "12:00 AM" would be misleading.
    if (d.hour == 0 && d.minute == 0 && d.second == 0) {
      return DateFormat('dd MMM yyyy').format(d);
    }
    return DateFormat('dd MMM yyyy, hh:mm a').format(d);
  }

  String _methodLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.transfer:
        return 'Transfer';
      case PaymentMethod.pos:
        return 'POS';
      case PaymentMethod.cheque:
        return 'Cheque';
      case PaymentMethod.mobileMoney:
        return 'Mobile Money';
      case PaymentMethod.savings:
        return 'Savings';
    }
  }

  Color _statusColor(PaymentStatus s) {
    return s == PaymentStatus.completed ? Colors.green : Colors.red;
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Payment Details',
                style: Theme.of(ctx).textTheme.titleLarge),
            const Divider(height: 32),
            _detailRow('Receipt No.', payment.receiptNumber),
            _detailRow('Amount', '$_currency${payment.amount.toStringAsFixed(2)}'),
            _detailRow('Date', _formatDate(payment.paymentDate)),
            _detailRow('Method', _methodLabel(payment.method)),
            _detailRow('Collector', payment.collector),
            if (payment.referenceNumber != null)
              _detailRow('Reference', payment.referenceNumber!),
            _detailRow('Status', payment.status.name.toUpperCase()),
            if (payment.remarks != null && payment.remarks!.isNotEmpty) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Notes',
                    style: Theme.of(ctx).textTheme.titleSmall),
              ),
              const SizedBox(height: 8),
              Text(payment.remarks!,
                  style: Theme.of(ctx).textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareReceipt(ctx),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share Receipt'),
                  ),
                ),
                if (payment.status != PaymentStatus.reversed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _editNotes(ctx),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Edit Notes'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _shareReceipt(BuildContext context) {
    final buffer = StringBuffer()
      ..writeln('ADEGHE PROFESSIONAL SERVICES')
      ..writeln('OFFICIAL PAYMENT RECEIPT')
      ..writeln()
      ..writeln('Receipt No: ${payment.receiptNumber}')
      ..writeln('Date: ${_formatDate(payment.paymentDate)}')
      ..writeln('Amount: $_currency${payment.amount.toStringAsFixed(2)}')
      ..writeln('Method: ${_methodLabel(payment.method)}')
      ..writeln('Collector: ${payment.collector}')
      ..writeln('Status: ${payment.status.name.toUpperCase()}');
    if (payment.referenceNumber != null) {
      buffer.writeln('Reference: ${payment.referenceNumber}');
    }
    if (payment.remarks != null && payment.remarks!.isNotEmpty) {
      buffer.writeln('Notes: ${payment.remarks}');
    }
    buffer.writeln();
    buffer.writeln('Thank you for your patronage.');
    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Payment Receipt - ${payment.receiptNumber}',
    ));
  }

  Future<void> _editNotes(BuildContext context) async {
    final ctrl = TextEditingController(text: payment.remarks ?? '');
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Notes'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'Add remarks...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null || !context.mounted) return;
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      await repo.updatePaymentNotes(
          payment.id,
          updated.isEmpty ? null : updated);
      ref.invalidate(paymentsForLoanProvider(payment.loanId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update notes: $e')),
        );
      }
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(value, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReversal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverse Payment'),
        content: Text(
          'Are you sure you want to reverse payment ${payment.receiptNumber} '
          'of $_currency${payment.amount.toStringAsFixed(2)}? This will restore '
          'the amount to the outstanding balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      await repo.reversePayment(payment.id);
      ref.invalidate(paymentsForLoanProvider(payment.loanId));
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(collectionListProvider);
      invalidateReportData(ref.invalidate);
      ref.invalidate(futureScheduleProvider);
      ref.invalidate(weeklyCollectionListProvider);
      ref.invalidate(loanDetailsProvider(payment.loanId));
      ref.invalidate(loanScheduleProvider(payment.loanId));
      ref.invalidate(activeLoansForCustomerProvider(customerId));
      ref.invalidate(savingsBalanceProvider(customerId));
      ref.invalidate(savingsTransactionsProvider(customerId));
      ref.invalidate(allSavingsAccountsProvider);
      ref.invalidate(allAccountsWithNamesProvider);
      ref.invalidate(customerProvider(customerId));
      ref.invalidate(customerListProvider);
      ref.invalidate(allLoansProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment reversed successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reverse: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReversed = payment.status == PaymentStatus.reversed;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(context),
        onLongPress: isReversed ? null : () => _confirmReversal(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    isReversed ? Colors.red.shade50 : Colors.green.shade50,
                child: Icon(
                  isReversed ? Icons.undo : Icons.check_circle_outline,
                  color: isReversed ? Colors.red : Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(payment.paymentDate),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_currency${payment.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_methodLabel(payment.method)}  \u2022  ${payment.receiptNumber}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(payment.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  payment.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(payment.status),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
