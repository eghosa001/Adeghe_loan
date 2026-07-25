import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/payment_entity.dart';
import '../providers/payment_providers.dart';


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
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: payments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _PaymentCard(payment: payments[index], ref: ref),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No payments recorded yet',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.ref});

  final Payment payment;
  final WidgetRef ref;

  String _formatDate(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);

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
        initialChildSize: 0.5,
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
            _detailRow('Amount', '\u20A6${payment.amount.toStringAsFixed(2)}'),
            _detailRow('Date', _formatDate(payment.paymentDate)),
            _detailRow('Method', _methodLabel(payment.method)),
            _detailRow('Collector', payment.collector),
            if (payment.referenceNumber != null)
              _detailRow('Reference', payment.referenceNumber!),
            _detailRow('Status', payment.status.name.toUpperCase()),
          ],
        ),
      ),
    );
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
          'of \u20A6${payment.amount.toStringAsFixed(2)}? This will restore '
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
      final repo = ref.read(paymentRepositoryProvider);
      await repo.reversePayment(payment.id);
      ref.invalidate(paymentsForLoanProvider(payment.loanId));
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
                      '\u20A6${payment.amount.toStringAsFixed(2)}',
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
