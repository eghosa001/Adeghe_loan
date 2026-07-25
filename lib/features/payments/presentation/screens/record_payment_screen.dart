import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/payment_entity.dart';
import '../providers/payment_providers.dart';

class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.loanId, required this.customerId, required this.currentBalance});

  final String loanId;
  final String customerId;
  final double currentBalance;

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
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

  Future<void> _savePayment() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) {
      return _showMessage('Enter a valid payment amount.');
    }
    setState(() => _loading = true);
    try {
      final repo = ref.read(paymentRepositoryProvider);
      final payment = await repo.createPayment(
        loanId: widget.loanId,
        customerId: widget.customerId,
        amount: amount,
        method: _method,
        referenceNumber: _method == PaymentMethod.cash ? null : _referenceCtrl.text.trim(),
        collector: 'Admin',
      );
      if (mounted) {
        _showMessage('Payment recorded: ${payment.receiptNumber}');
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Text('Outstanding balance: ${widget.currentBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Amount paid', prefixText: '\u20A6'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentMethod>(
              value: _method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: PaymentMethod.values
                  .map((method) => DropdownMenuItem(value: method, child: Text(method.name.toUpperCase())))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            if (_method != PaymentMethod.cash) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _referenceCtrl,
                decoration: const InputDecoration(labelText: 'Reference number'),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _savePayment,
              child: _loading ? const CircularProgressIndicator() : const Text('Submit payment'),
            ),
          ],
        ),
      ),
    );
  }
}
