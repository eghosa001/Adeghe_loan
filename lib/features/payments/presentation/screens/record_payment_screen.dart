import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../business/presentation/providers/business_providers.dart';
import '../../data/models/payment_entity.dart';
import '../providers/payment_providers.dart';
import '../../../collection/presentation/providers/collection_provider.dart';
import '../../../customers/presentation/providers/customer_providers.dart';
import '../../../dashboard/presentation/providers/dashboard_provider.dart';
import '../../../loans/presentation/providers/loan_providers.dart';
import '../../../reports/presentation/providers/report_provider.dart';
import '../../../savings/presentation/providers/savings_providers.dart';

class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.loanId,
    required this.customerId,
    required this.currentBalance,
    this.installmentDue,
    this.initialAmount,
  });

  final String loanId;
  final String customerId;
  final double currentBalance;
  /// The expected installment amount for today (or the next due installment).
  final double? installmentDue;
  /// Pre-fill the payment amount field.
  final double? initialAmount;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _amountCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _loading = false;

  /// Idempotency key for this payment. It is created once when the screen
  /// opens and reused on every submit attempt, so a double-tap or a retry of
  /// the same submission is recorded as a single payment, never a duplicate.
  final String _requestId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amountCtrl.text = widget.initialAmount!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _referenceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _enteredAmount => double.tryParse(_amountCtrl.text) ?? 0;

  /// Surplus is compared against the current installment (falling back to the
  /// outstanding balance when no installment context is available).
  double get _surplus {
    final entered = _enteredAmount;
    if (entered <= 0) return 0.0;
    final cap = (widget.installmentDue != null && widget.installmentDue! > 0)
        ? widget.installmentDue!
        : widget.currentBalance;
    return (entered - cap).clamp(0.0, double.infinity);
  }

  bool get _isOverpayment => _surplus > 0.001;

  Future<void> _savePayment() async {
    final amount = _enteredAmount;
    if (!amount.isFinite || amount <= 0) {
      return _showMessage('Enter a valid payment amount.');
    }
    setState(() => _loading = true);
    try {
      final repo = await ref.read(paymentRepositoryProvider.future);
      final profileAsync = ref.read(businessProfileProvider);
      final collectorName = profileAsync.valueOrNull?.ownerName ?? 'Admin';
      final payment = await repo.createPayment(
        loanId: widget.loanId,
        customerId: widget.customerId,
        amount: amount,
        method: _method,
        referenceNumber:
            _method == PaymentMethod.cash ? null : _referenceCtrl.text.trim(),
        collector: collectorName,
        remarks: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        installmentDue: widget.installmentDue,
        clientRequestId: _requestId,
      );
      if (mounted) {
        _showMessage('Payment recorded: ${payment.receiptNumber}'
            '${_isOverpayment ? '\n${CurrencyUtils.format(_surplus)} credited to savings.' : ''}');
        ref.invalidate(dashboardDataProvider);
        ref.invalidate(collectionListProvider);
        ref.invalidate(loanDetailsProvider(widget.loanId));
        ref.invalidate(paymentsForLoanProvider(widget.loanId));
        ref.invalidate(loanScheduleProvider(widget.loanId));
        ref.invalidate(savingsBalanceProvider(widget.customerId));
        ref.invalidate(savingsTransactionsProvider(widget.customerId));
        ref.invalidate(allSavingsAccountsProvider);
        ref.invalidate(allAccountsWithNamesProvider);
        ref.invalidate(customerProvider(widget.customerId));
        ref.invalidate(customerListProvider);
        ref.invalidate(reportSummaryProvider);
        ref.invalidate(activeLoansForCustomerProvider(widget.customerId));
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
    final currency = ref.watch(currencySymbolProvider).valueOrNull ??
        CurrencyUtils.defaultSymbol;
    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
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
                prefixText: currency,
                suffixIcon: _isOverpayment
                    ? const Icon(Icons.savings_outlined, color: Colors.green)
                    : null,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
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
                            '${CurrencyUtils.format(_surplus)} over the installment will be credited to this customer\'s savings account.',
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
              initialValue: _method,
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
                inputFormatters:
                    textFormatters(maxLength: AppConstants.maxReferenceLength),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Add payment remarks...',
              ),
              maxLines: 2,
              maxLength: AppConstants.maxNotesLength,
              inputFormatters: const [NoControlCharactersFormatter()],
            ),
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
