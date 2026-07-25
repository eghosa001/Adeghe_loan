import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/domain/loan_calculator.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';

class LoanCreationScreen extends ConsumerWidget {
  final String customerId;
  const LoanCreationScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(loanFormProvider);
    final formNotifier = ref.read(loanFormProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Loan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              try {
                await formNotifier.saveLoan(customerId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loan created successfully!')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              }
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Loan type: Daily or Weekly
          SegmentedButton<LoanType>(
            segments: const [
              ButtonSegment(value: LoanType.daily, label: Text('Daily')),
              ButtonSegment(value: LoanType.weekly, label: Text('Weekly')),
            ],
            selected: {formState.loanType},
            onSelectionChanged: (selection) {
              formNotifier.updateField(loanType: selection.first);
            },
          ),
          const SizedBox(height: 16),

          // Input Fields
          _buildTextField(
            label: 'Loan Amount (Principal)',
            onChanged: (value) => formNotifier.updateField(
                principal: double.tryParse(value) ?? 0.0),
          ),
          _buildTextField(
            label: 'Interest Rate (%)',
            onChanged: (value) => formNotifier.updateField(
                interestRatePercent: double.tryParse(value) ?? 0.0),
          ),
          _buildTextField(
            label: formState.loanType == LoanType.daily
                ? 'Duration (Days)'
                : 'Duration (Weeks)',
            onChanged: (value) =>
                formNotifier.updateField(duration: int.tryParse(value) ?? 0),
          ),

          // Start Date
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repayment Start Date'),
            subtitle: Text(AppDateUtils.formatDate(formState.repaymentStartDate)),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: formState.repaymentStartDate,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (pickedDate != null) {
                formNotifier.updateField(repaymentStartDate: pickedDate);
              }
            },
          ),
          const Divider(height: 32),

          // Calculation Summary
          if (formState.calculationResult != null)
            _buildSummary(formState.calculationResult!),
        ],
      ),
    );
  }

  Widget _buildTextField(
      {required String label, required ValueChanged<String> onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSummary(LoanCalculationResult result) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Loan Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _summaryRow('Interest:', CurrencyUtils.format(result.interestAmount)),
            _summaryRow('Total Charges:', CurrencyUtils.format(result.totalCharges)),
            const Divider(),
            _summaryRow('Total Repayment:',
                CurrencyUtils.format(result.totalRepayment),
                isBold: true),
            _summaryRow(
                'Installment:', CurrencyUtils.format(result.installmentAmount),
                isBold: true),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    final style = TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
