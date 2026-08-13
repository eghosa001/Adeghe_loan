import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/core/utils/input_formatters.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';

class LoanCreationScreen extends ConsumerStatefulWidget {
  final String customerId;
  final Loan? existingLoan;
  const LoanCreationScreen({
    super.key,
    required this.customerId,
    this.existingLoan,
  });

  @override
  ConsumerState<LoanCreationScreen> createState() => _LoanCreationScreenState();
}

class _LoanCreationScreenState extends ConsumerState<LoanCreationScreen> {
  bool _hasLoaded = false;

  // Controllers seed the text fields when editing. Without them every field is
  // blank on the edit screen even though the form state was loaded — the user
  // was forced to retype the whole loan.
  final _principalCtrl = TextEditingController();
  final _interestCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _processingCtrl = TextEditingController();
  final _adminCtrl = TextEditingController();
  final _otherCtrl = TextEditingController();
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final loan = widget.existingLoan;
    if (loan != null) {
      _principalCtrl.text = _fmtAmount(loan.amount);
      _interestCtrl.text = _fmtAmount(loan.interestRate);
      _durationCtrl.text = loan.duration.toString();
      _insuranceCtrl.text = _fmtAmount(loan.insuranceFee);
      _commissionCtrl.text = _fmtAmount(loan.commission);
      _processingCtrl.text = _fmtAmount(loan.processingFee);
      _adminCtrl.text = _fmtAmount(loan.administrativeFee);
      _otherCtrl.text = _fmtAmount(loan.otherCharges);
      if (loan.customCollectionAmount != null &&
          loan.customCollectionAmount! > 0) {
        _customCtrl.text = _fmtAmount(loan.customCollectionAmount!);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLoanForEdit());
    } else {
      // New loan: start from the fresh daily defaults so the fields show the
      // default terms and the summary is computed for them.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initCreateMode());
    }
  }

  /// Resets the form to the daily defaults and mirrors them into the visible
  /// text fields (the form notifier outlives this screen, so a previous visit
  /// may have left it on another type).
  void _initCreateMode() {
    if (!mounted) return;
    final notifier = ref.read(loanFormProvider.notifier);
    notifier.selectLoanType(LoanType.daily);
    final state = ref.read(loanFormProvider);
    _interestCtrl.text = _fmtAmount(state.interestRatePercent);
    _durationCtrl.text = state.duration.toString();
  }

  /// Whole values render without a trailing `.0`; small fractions keep them
  /// so the parse is lossless when the loan is saved again.
  static String _fmtAmount(double value) {
    return value == value.roundToDouble() && value.abs() < 1e12
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _principalCtrl.dispose();
    _interestCtrl.dispose();
    _durationCtrl.dispose();
    _insuranceCtrl.dispose();
    _commissionCtrl.dispose();
    _processingCtrl.dispose();
    _adminCtrl.dispose();
    _otherCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLoanForEdit() async {
    final loan = widget.existingLoan!;
    // loadForEdit clears any stale custom collection amount left by a
    // previous create/edit session when this loan has none.
    ref.read(loanFormProvider.notifier).loadForEdit(loan);
    setState(() => _hasLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(loanFormProvider);
    final formNotifier = ref.read(loanFormProvider.notifier);
    final isEdit = widget.existingLoan != null;

    if (isEdit && !_hasLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Loan')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Loan' : 'Create New Loan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              try {
                if (isEdit) {
                  await formNotifier.updateLoan(
                    widget.existingLoan!,
                    widget.customerId,
                  );
                } else {
                  await formNotifier.saveLoan(widget.customerId);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isEdit ? 'Loan updated!' : 'Loan created successfully!',
                      ),
                    ),
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
          ),
        ],
      ),
      body: KeyboardScrollable(
        child: ListView(
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
              final type = selection.first;
              // Apply the selected type's default interest rate and duration
              // and mirror them into the visible fields so the user can see
              // and change them.
              formNotifier.selectLoanType(type);
              final defaults = type == LoanType.daily
                  ? (
                      AppConstants.defaultDailyInterestRate,
                      AppConstants.defaultDailyDurationDays,
                    )
                  : (
                      AppConstants.defaultWeeklyInterestRate,
                      AppConstants.defaultWeeklyDurationWeeks,
                    );
              _interestCtrl.text = _fmtAmount(defaults.$1);
              _durationCtrl.text = defaults.$2.toString();
            },
          ),
          const SizedBox(height: 16),

          // Input Fields
          _buildTextField(
            label: 'Loan Amount (Principal)',
            controller: _principalCtrl,
            onChanged: (value) {
              formNotifier.updateField(
                principal: CurrencyUtils.tryParseAmount(value) ?? 0.0,
                clearCustomInstallment: true,
              );
              // Keep the visible field in sync with the state: the override is
              // intentionally invalidated when the principal changes, so the
              // still-typed amount must not linger and mislead the operator.
              _customCtrl.clear();
            },
          ),
          _buildTextField(
            label: 'Interest Rate (%)',
            controller: _interestCtrl,
            onChanged: (value) => formNotifier.updateField(
              interestRatePercent: CurrencyUtils.tryParseAmount(value) ?? 0.0,
            ),
          ),
          _buildTextField(
            label: formState.loanType == LoanType.daily
                ? 'Duration (Days)'
                : 'Duration (Weeks)',
            controller: _durationCtrl,
            onChanged: (value) {
              final parsedDuration = int.tryParse(value);
              formNotifier.updateField(
                duration:
                    (parsedDuration != null &&
                        parsedDuration > 0 &&
                        parsedDuration <= AppConstants.maxLoanDuration)
                    ? parsedDuration
                    : 0,
                clearCustomInstallment: true,
              );
              _customCtrl.clear();
            },
          ),
          ExpansionTile(
            title: const Text('Fees & charges'),
            children: [
              _buildTextField(
                label: 'Insurance fee (%)',
                controller: _insuranceCtrl,
                onChanged: (value) => formNotifier.updateField(
                  insuranceFeePercent:
                      CurrencyUtils.tryParseAmount(value) ?? 0.0,
                ),
              ),
              _buildTextField(
                label: 'Commission (%)',
                controller: _commissionCtrl,
                onChanged: (value) => formNotifier.updateField(
                  commissionPercent: CurrencyUtils.tryParseAmount(value) ?? 0.0,
                ),
              ),
              _buildTextField(
                label: 'Processing fee',
                controller: _processingCtrl,
                onChanged: (value) => formNotifier.updateField(
                  processingFee: CurrencyUtils.tryParseAmount(value) ?? 0.0,
                ),
              ),
              _buildTextField(
                label: 'Administrative fee',
                controller: _adminCtrl,
                onChanged: (value) => formNotifier.updateField(
                  administrativeFee: CurrencyUtils.tryParseAmount(value) ?? 0.0,
                ),
              ),
              _buildTextField(
                label: 'Other charges',
                controller: _otherCtrl,
                onChanged: (value) => formNotifier.updateField(
                  otherCharges: CurrencyUtils.tryParseAmount(value) ?? 0.0,
                ),
              ),
            ],
          ),

          // Custom collection amount
          _buildTextField(
            label: 'Collection amount per period (optional)',
            controller: _customCtrl,
            hint:
                'Amount to collect per period (default: ${CurrencyUtils.format(formState.calculationResult?.installmentAmount ?? 0)})',
            onChanged: (value) => formNotifier.updateField(
              customInstallmentAmount: CurrencyUtils.tryParsePositiveAmount(
                value,
              ),
            ),
          ),

          // Notes
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TextFormField(
              initialValue: formState.notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Additional notes about this loan',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: AppConstants.maxNotesLength,
              inputFormatters: const [NoControlCharactersFormatter()],
              onChanged: (value) => formNotifier.updateField(notes: value),
            ),
          ),

          // Start Date
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repayment Start Date'),
            subtitle: Text(
              AppDateUtils.formatDate(formState.repaymentStartDate),
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: formState.repaymentStartDate,
                firstDate: DateTime.now().subtract(const Duration(days: 180)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (pickedDate != null) {
                formNotifier.updateField(repaymentStartDate: pickedDate);
              }
            },
          ),
          const Divider(height: 32),

          // Calculation Summary
          if (formState.calculationResult != null) _buildSummary(formState),
        ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        keyboardType: TextInputType.number,
        inputFormatters: const [NoControlCharactersFormatter()],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSummary(LoanFormData formState) {
    final result = formState.calculationResult!;
    final calculatedInstallment = result.installmentAmount;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Loan Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _summaryRow(
              'Interest:',
              CurrencyUtils.format(result.interestAmount),
            ),
            _summaryRow(
              'Total Charges:',
              CurrencyUtils.format(result.totalCharges),
            ),
            const Divider(),
            _summaryRow(
              'Total Repayment:',
              CurrencyUtils.format(result.totalRepayment),
              isBold: true,
            ),
            _summaryRow(
              'Installment:',
              CurrencyUtils.format(calculatedInstallment),
              isBold: true,
            ),
            if (formState.customInstallmentAmount != null &&
                formState.customInstallmentAmount! > 0)
              _summaryRow(
                'Collection amount:',
                CurrencyUtils.format(formState.customInstallmentAmount!),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false}) {
    final style = TextStyle(
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      fontSize: 16,
    );
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
