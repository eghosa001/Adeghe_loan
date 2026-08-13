import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/utils/input_formatters.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';
import '../providers/business_providers.dart';
import '../../data/models/financial_settings_entity.dart';

class FinancialSettingsTab extends ConsumerStatefulWidget {
  const FinancialSettingsTab({super.key});
  @override
  ConsumerState<FinancialSettingsTab> createState() =>
      _FinancialSettingsTabState();
}

class _FinancialSettingsTabState extends ConsumerState<FinancialSettingsTab> {
  final _formKey = GlobalKey<FormState>();
  final _currencyCtrl = TextEditingController();
  final _interestCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _processingCtrl = TextEditingController();
  final _penaltyCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  String _loanType = 'daily';
  bool _hasPrefilled = false;
  bool _isEditing = false;

  @override
  void dispose() {
    _currencyCtrl.dispose();
    _interestCtrl.dispose();
    _insuranceCtrl.dispose();
    _commissionCtrl.dispose();
    _processingCtrl.dispose();
    _penaltyCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _prefill(FinancialSettings s) {
    if (_hasPrefilled) return;
    _currencyCtrl.text = s.currency;
    _interestCtrl.text = s.defaultInterestRate.toString();
    _insuranceCtrl.text = s.defaultInsuranceFee.toString();
    _commissionCtrl.text = s.defaultCommission.toString();
    _processingCtrl.text = s.defaultProcessingFee.toString();
    _penaltyCtrl.text = s.defaultPenaltyRules;
    _durationCtrl.text = s.defaultLoanDurationDays.toString();
    // Sanitize legacy values (e.g. a pre-v15 'monthly' row): the dropdown only
    // offers daily/weekly, and `DropdownButtonFormField.initialValue` throws if
    // the value is not among the items.
    _loanType = s.defaultLoanType == 'weekly' ? 'weekly' : 'daily';
    _hasPrefilled = true;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final interest = double.tryParse(_interestCtrl.text.trim()) ?? double.nan;
    final insurance =
        double.tryParse(_insuranceCtrl.text.trim()) ?? double.nan;
    final commission =
        double.tryParse(_commissionCtrl.text.trim()) ?? double.nan;
    final processing =
        double.tryParse(_processingCtrl.text.trim()) ?? double.nan;
    final duration =
        int.tryParse(_durationCtrl.text.trim()) ?? -1;
    // Reject NaN/±Infinity (double.tryParse returns Infinity for "1e309")
    // and negative values, and cap the duration so the default can never
    // pre-fill an unbounded loan schedule.
    if (!interest.isFinite || interest < 0 ||
        !insurance.isFinite || insurance < 0 ||
        !commission.isFinite || commission < 0 ||
        !processing.isFinite || processing < 0 ||
        duration < 1 || duration > AppConstants.maxLoanDuration) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter valid numeric values')));
      }
      return;
    }

    final map = {
      'currency': _currencyCtrl.text.trim(),
      'default_interest': interest.toString(),
      'default_insurance': insurance.toString(),
      'default_commission': commission.toString(),
      'default_processing': processing.toString(),
      'default_penalty_rules': _penaltyCtrl.text.trim(),
      'default_loan_duration_days': duration.toString(),
      'default_loan_type': _loanType,
    };
    final repo = await ref.read(businessRepoProvider.future);
    await repo.saveSettings(map);
    ref.invalidate(financialSettingsProvider);
    if (!mounted) return;
    setState(() {
      _isEditing = false;
      _hasPrefilled = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Financial defaults saved')));
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsView(FinancialSettings settings) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Icon(Icons.attach_money_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 24),
        _buildDetailRow('Currency', settings.currency),
        const Divider(),
        _buildDetailRow(
            'Interest Rate', '${settings.defaultInterestRate}%'),
        const Divider(),
        _buildDetailRow(
            'Insurance Fee', settings.defaultInsuranceFee.toString()),
        const Divider(),
        _buildDetailRow(
            'Commission', settings.defaultCommission.toString()),
        const Divider(),
        _buildDetailRow(
            'Processing Fee', settings.defaultProcessingFee.toString()),
        const Divider(),
        _buildDetailRow('Penalty Rules', settings.defaultPenaltyRules),
        const Divider(),
        _buildDetailRow('Loan Duration (days)',
            settings.defaultLoanDurationDays.toString()),
        const Divider(),
        _buildDetailRow('Loan Type',
            settings.defaultLoanType.toUpperCase()),
      ],
    );
  }

  Widget _buildEditForm(FinancialSettings settings) {
    _prefill(settings);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            TextFormField(
                controller: _currencyCtrl,
                decoration:
                    const InputDecoration(labelText: 'Currency Symbol'),
                maxLength: 8,
                inputFormatters: const [NoControlCharactersFormatter()],
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            TextFormField(
                controller: _interestCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Interest Rate (%)'),
                keyboardType:
                    TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _insuranceCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Insurance Fee'),
                keyboardType:
                    TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _commissionCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Commission'),
                keyboardType:
                    TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _processingCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Processing Fee'),
                keyboardType:
                    TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _penaltyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Penalty Rules (JSON/text)'),
                maxLines: 3,
                maxLength: AppConstants.maxNotesLength,
                inputFormatters: const [NoControlCharactersFormatter()]),
            const SizedBox(height: 16),
            const Divider(),
            const Text('Loan Defaults',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 12),
            TextFormField(
                controller: _durationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Default Loan Duration (days)'),
                keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _loanType,
              decoration: const InputDecoration(labelText: 'Default Loan Type'),
              items: const [
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _loanType = v);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: _save, child: const Text('Save Defaults')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(financialSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Defaults')),
      body: KeyboardScrollable(
        child: settingsAsync.when(
          data: (settings) => _isEditing
              ? _buildEditForm(settings)
              : _buildSettingsView(settings),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: Text('Error loading settings: $error')),
        ),
      ),
      floatingActionButton: settingsAsync.whenOrNull(
        data: (_) => FloatingActionButton(
          onPressed: () {
            if (_isEditing) {
              if (_formKey.currentState?.validate() ?? false) {
                _save();
              }
            } else {
              setState(() {
                _isEditing = true;
                _hasPrefilled = false;
              });
            }
          },
          child: Icon(_isEditing ? Icons.check : Icons.edit),
        ),
      ),
    );
  }
}
