import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../data/models/payment_entity.dart';
import '../providers/payment_providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../savings/presentation/providers/savings_providers.dart';

class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.loanId,
    required this.customerId,
    required this.currentBalance,
    this.installmentDue,
  });

  final String loanId;
  final String customerId;
  final double currentBalance;
  /// The expected installment amount for today (or the next due installment).
  final double? installmentDue;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  double get _enteredAmount => double.tryParse(_amountCtrl.text) ?? 0;

  double get _surplus {
    final entered = _enteredAmount;
    // Surplus compared to full outstanding balance
    return (entered - widget.currentBalance).clamp(0.0, double.infinity);
  }

  bool get _isOverpayment => _surplus > 0.001;

  Future<void> _savePayment() async {
    final amount = _enteredAmount;
    if (amount <= 0) {
      return _showMessage('Enter a valid payment amount.');
    }
    setState(() => _loading = true);
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      final payment = await repo.createPayment(
        loanId: widget.loanId,
        customerId: widget.customerId,
        amount: amount,
        method: _method,
        referenceNumber:
            _method == PaymentMethod.cash ? null : _referenceCtrl.text.trim(),
        collector: 'Admin',
      );
      if (mounted) {
        _showMessage('Payment recorded: ${payment.receiptNumber}'
            '${_isOverpayment ? '\n${CurrencyUtils.format(_surplus)} credited to savings.' : ''}');
        ref.invalidate(dashboardDataProvider);
        ref.invalidate(collectionListProvider);
        ref.invalidate(loanDetailsProvider(widget.loanId));
        ref.invalidate(paymentsForLoanProvider(widget.loanId));
        ref.invalidate(savingsBalanceProvider(widget.customerId));
        ref.invalidate(savingsTransactionsProvider(widget.customerId));
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showMessage('Unable to record payment: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Outstanding balance card
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding Balance',
                        style: Theme.of(context).textTheme.labelLarge),
                    Text(
                      CurrencyUtils.format(widget.currentBalance),
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (widget.installmentDue != null) ...[
                      const SizedBox(height: 4),
                      Text(
                          'Installment due: ${CurrencyUtils.format(widget.installmentDue!)}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Quick fill buttons
            if (widget.installmentDue != null &&
                widget.installmentDue! < widget.currentBalance) ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _amountCtrl.text =
                        widget.installmentDue!.toStringAsFixed(0)),
                    child: Text(
                        'Fill installment (${CurrencyUtils.format(widget.installmentDue!)})'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _amountCtrl.text =
                        widget.currentBalance.toStringAsFixed(0)),
                    child: const Text('Pay in full'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _amountCtrl,
              decoration: InputDecoration(
                labelText: 'Amount paid',
                prefixText: '₦',
                suffixIcon: _isOverpayment
                    ? const Icon(Icons.savings_outlined, color: Colors.green)
                    : null,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
            // Overpayment hint
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isOverpayment
                  ? Padding(
                      key: const ValueKey('hint'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${CurrencyUtils.format(_surplus)} over the outstanding balance will be credited to this customer\'s savings account.',
                            style: const TextStyle(
                                color: Colors.green, fontSize: 12),
                          ),
                        ),
                      ]),
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              value: _method,
              decoration:
                  const InputDecoration(labelText: 'Payment method'),
              items: PaymentMethod.values
                  .map((method) => DropdownMenuItem(
                      value: method,
                      child: Text(method.name.toUpperCase())))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            if (_method != PaymentMethod.cash) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _referenceCtrl,
                decoration:
                    const InputDecoration(labelText: 'Reference number'),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _savePayment,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Submit payment'),
            ),
          ],
        ),
      ),
    );
  }
}
