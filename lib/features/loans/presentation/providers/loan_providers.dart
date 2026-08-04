import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/features/customers/presentation/providers/customer_providers.dart';
import 'package:loantrack/features/dashboard/presentation/providers/dashboard_provider.dart';
import 'package:loantrack/features/collection/presentation/providers/collection_provider.dart';
import 'package:loantrack/features/reports/presentation/providers/report_provider.dart';
import 'package:loantrack/core/utils/currency_utils.dart';
import 'package:loantrack/features/holidays/presentation/providers/holiday_provider.dart';
import 'package:loantrack/features/loans/data/loan_repository.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:loantrack/features/loans/domain/loan_calculator.dart';
import 'package:loantrack/features/loans/domain/schedule_generator.dart';

// ---------------------------------------------------------------------------
// Loan Form
// ---------------------------------------------------------------------------

@immutable
class LoanFormData {
  final LoanType loanType;
  final double principal;
  final double interestRatePercent;
  final double insuranceFeePercent;
  final double commissionPercent;
  final double processingFee;
  final double administrativeFee;
  final double otherCharges;
  final int duration;
  final DateTime repaymentStartDate;
  final LoanCalculationResult? calculationResult;
  final double? customInstallmentAmount;
  final String notes;

  const LoanFormData({
    this.loanType = LoanType.daily,
    this.principal = 0.0,
    this.interestRatePercent = 0.0,
    this.insuranceFeePercent = 0.0,
    this.commissionPercent = 0.0,
    this.processingFee = 0.0,
    this.administrativeFee = 0.0,
    this.otherCharges = 0.0,
    this.duration = 0,
    required this.repaymentStartDate,
    this.calculationResult,
    this.customInstallmentAmount,
    this.notes = '',
  });

  LoanFormData copyWith({
    LoanType? loanType,
    double? principal,
    double? interestRatePercent,
    double? insuranceFeePercent,
    double? commissionPercent,
    double? processingFee,
    double? administrativeFee,
    double? otherCharges,
    int? duration,
    DateTime? repaymentStartDate,
    LoanCalculationResult? calculationResult,
    double? customInstallmentAmount,
    bool clearCustomInstallment = false,
    String? notes,
  }) {
    return LoanFormData(
      loanType: loanType ?? this.loanType,
      principal: principal ?? this.principal,
      interestRatePercent: interestRatePercent ?? this.interestRatePercent,
      insuranceFeePercent: insuranceFeePercent ?? this.insuranceFeePercent,
      commissionPercent: commissionPercent ?? this.commissionPercent,
      processingFee: processingFee ?? this.processingFee,
      administrativeFee: administrativeFee ?? this.administrativeFee,
      otherCharges: otherCharges ?? this.otherCharges,
      duration: duration ?? this.duration,
      repaymentStartDate: repaymentStartDate ?? this.repaymentStartDate,
      calculationResult: calculationResult ?? this.calculationResult,
      customInstallmentAmount: clearCustomInstallment
          ? null
          : (customInstallmentAmount ?? this.customInstallmentAmount),
      notes: notes ?? this.notes,
    );
  }

  /// Returns the effective installment amount: user override if set, otherwise auto-calculated.
  double get effectiveInstallment {
    if (customInstallmentAmount != null && customInstallmentAmount! > 0) {
      return customInstallmentAmount!;
    }
    return calculationResult?.installmentAmount ?? 0.0;
  }
}

class LoanFormNotifier extends StateNotifier<LoanFormData> {
  LoanFormNotifier(this._ref)
      : super(LoanFormData(repaymentStartDate: DateTime.now()));

  final Ref _ref;

  void updateField({
    LoanType? loanType,
    double? principal,
    double? interestRatePercent,
    double? insuranceFeePercent,
    double? commissionPercent,
    double? processingFee,
    double? administrativeFee,
    double? otherCharges,
    int? duration,
    DateTime? repaymentStartDate,
    double? customInstallmentAmount,
    bool clearCustomInstallment = false,
    String? notes,
  }) {
    state = state.copyWith(
      loanType: loanType,
      principal: principal,
      interestRatePercent: interestRatePercent,
      insuranceFeePercent: insuranceFeePercent,
      commissionPercent: commissionPercent,
      processingFee: processingFee,
      administrativeFee: administrativeFee,
      otherCharges: otherCharges,
      duration: duration,
      repaymentStartDate: repaymentStartDate,
      customInstallmentAmount: customInstallmentAmount,
      clearCustomInstallment: clearCustomInstallment,
      notes: notes,
    );
    if (loanType != null || principal != null || interestRatePercent != null ||
        insuranceFeePercent != null || commissionPercent != null ||
        processingFee != null || administrativeFee != null ||
        otherCharges != null || duration != null) {
      _recalculate();
    }
  }

  void _recalculate() {
    final result = LoanCalculator.calculate(
      principal: state.principal,
      interestRatePercent: state.interestRatePercent,
      insuranceFeePercent: state.insuranceFeePercent,
      commissionPercent: state.commissionPercent,
      processingFee: state.processingFee,
      administrativeFee: state.administrativeFee,
      otherCharges: state.otherCharges,
      duration: state.duration,
    );
    state = state.copyWith(calculationResult: result);
  }

  /// Builds the [Loan] and its repayment schedule from the current form state.
  ///
  /// Guarantees the schedule sum exactly equals `total_repayment` so the loan
  /// can reach `completed`:
  /// - a custom collection amount redefines the repayment total as
  ///   `customAmount × duration`, and
  /// - per-installment amounts come from `CurrencyUtils.splitEvenly` so any
  ///   rounding remainder is distributed instead of silently dropped.
  Future<({Loan loan, List<RepaymentInstallment> schedule})>
      _buildLoanFromForm(String customerId, String loanId) async {
    if (state.calculationResult == null || state.duration <= 0) {
      throw Exception("Cannot save loan with invalid data.");
    }

    final effectiveInstallment = state.effectiveInstallment;
    if (effectiveInstallment <= 0) {
      throw Exception("Installment amount must be greater than zero.");
    }

    final customAmount = state.customInstallmentAmount;
    final isCustom = customAmount != null && customAmount > 0;
    final totalRepayment = isCustom
        ? CurrencyUtils.roundToCents(effectiveInstallment * state.duration)
        : state.calculationResult!.totalRepayment;

    final amounts = CurrencyUtils.splitEvenly(totalRepayment, state.duration);

    final holidays = await _ref.read(holidayListProvider.future);
    final schedule = ScheduleGenerator.generate(
      loanId: loanId,
      loanType: state.loanType,
      startDate: state.repaymentStartDate,
      amounts: amounts,
      holidays: holidays,
    );

    if (schedule.isEmpty) {
      throw Exception("Could not generate a repayment schedule.");
    }

    final loan = Loan(
      id: loanId,
      customerId: customerId,
      loanType: state.loanType,
      amount: state.principal,
      interestRate: state.interestRatePercent,
      insuranceFee: state.insuranceFeePercent,
      commission: state.commissionPercent,
      processingFee: state.processingFee,
      administrativeFee: state.administrativeFee,
      otherCharges: state.otherCharges,
      duration: state.duration,
      loanDate: DateTime.now(),
      repaymentStartDate: state.repaymentStartDate,
      totalRepayment: totalRepayment,
      outstandingBalance: totalRepayment,
      installmentAmount: effectiveInstallment,
      expectedCompletionDate: schedule.last.dueDate,
      notes: state.notes.isNotEmpty ? state.notes : null,
      customCollectionAmount: isCustom ? customAmount : null,
    );

    return (loan: loan, schedule: schedule);
  }

  Future<void> saveLoan(String customerId) async {
    final loanId = 'L-${DateTime.now().microsecondsSinceEpoch}';
    final (:loan, :schedule) = await _buildLoanFromForm(customerId, loanId);
    final loanRepo = await _ref.read(loanRepositoryProvider.future);

    final result = await loanRepo.saveLoanAndSchedule(loan, schedule);
    result.when(
      success: (_) {
        _ref.invalidate(dashboardDataProvider);
        _ref.invalidate(customerListProvider);
        _ref.invalidate(customerProvider(customerId));
        _ref.invalidate(collectionListProvider);
        _ref.invalidate(reportSummaryProvider);
        _ref.invalidate(activeLoansForCustomerProvider(customerId));
        logAuditAction(_ref, 'CREATE',
            'Loan $loanId created for customer $customerId — ${state.loanType.name}, ${state.principal}');
        state = LoanFormData(repaymentStartDate: DateTime.now());
      },
      failure: (f) => throw f,
    );
  }

  Future<void> updateLoan(Loan existingLoan, String customerId) async {
    final (:loan, :schedule) =
        await _buildLoanFromForm(customerId, existingLoan.id);
    final loanRepo = await _ref.read(loanRepositoryProvider.future);

    // Preserve the original loan date and credit any amount already paid.
    final paidSoFar = (existingLoan.totalRepayment -
            existingLoan.outstandingBalance)
        .clamp(0.0, double.infinity);
    final newOutstanding =
        (loan.totalRepayment - paidSoFar).clamp(0.0, double.infinity);
    final status = existingLoan.status == LoanStatus.active
        ? (newOutstanding <= 0.005 ? LoanStatus.completed : LoanStatus.active)
        : existingLoan.status;
    final updatedLoan = loan.copyWith(
      loanDate: existingLoan.loanDate,
      outstandingBalance: newOutstanding,
      status: status,
    );

    final result =
        await loanRepo.updateLoanAndSchedule(updatedLoan, schedule,
            paidSoFar: paidSoFar);
    result.when(
      success: (_) {
        _ref.invalidate(loanDetailsProvider(existingLoan.id));
        _ref.invalidate(dashboardDataProvider);
        _ref.invalidate(customerListProvider);
        _ref.invalidate(customerProvider(customerId));
        _ref.invalidate(collectionListProvider);
        _ref.invalidate(reportSummaryProvider);
        _ref.invalidate(activeLoansForCustomerProvider(customerId));
        _ref.invalidate(allLoansProvider);
        logAuditAction(_ref, 'UPDATE',
            'Loan ${existingLoan.id} updated for customer $customerId');
        state = LoanFormData(repaymentStartDate: DateTime.now());
      },
      failure: (f) => throw f,
    );
  }
}

final loanFormProvider =
    StateNotifierProvider<LoanFormNotifier, LoanFormData>((ref) {
  return LoanFormNotifier(ref);
});

// ---------------------------------------------------------------------------
// Loan Details
// ---------------------------------------------------------------------------

final loanDetailsProvider =
    FutureProvider.family<Loan, String>((ref, loanId) async {
  final repo = await ref.watch(loanRepositoryProvider.future);
  final result = await repo.getLoanById(loanId);
  return result.when(
    success: (loan) => loan,
    failure: (f) => throw f,
  );
});

final loanScheduleProvider =
    FutureProvider.family<List<RepaymentInstallment>, String>((ref, loanId) async {
  final repo = await ref.watch(loanRepositoryProvider.future);
  final result = await repo.getScheduleForLoan(loanId);
  return result.when(
    success: (schedule) => schedule,
    failure: (f) => throw f,
  );
});

final activeLoansForCustomerProvider =
    FutureProvider.family<List<Loan>, String>((ref, customerId) async {
  final repo = await ref.watch(loanRepositoryProvider.future);
  final result = await repo.getActiveLoansForCustomer(customerId);
  return result.when(
    success: (loans) => loans,
    failure: (f) => throw f,
  );
});

/// All loans for a customer (any status) — used by statements so history is
/// not hidden once a loan is completed.
final allLoansForCustomerProvider =
    FutureProvider.family<List<Loan>, String>((ref, customerId) async {
  final repo = await ref.watch(loanRepositoryProvider.future);
  final result = await repo.getLoansForCustomer(customerId);
  return result.when(
    success: (loans) => loans,
    failure: (f) => throw f,
  );
});

// ---------------------------------------------------------------------------
// All Loans (global list with search & status filter)
// ---------------------------------------------------------------------------

final loanSearchQueryProvider = StateProvider<String>((ref) => '');

final loanStatusFilterProvider = StateProvider<String?>((ref) => null);

final loanTypeFilterProvider = StateProvider<String?>((ref) => null);

final allLoansProvider = FutureProvider<List<Loan>>((ref) async {
  final repo = await ref.watch(loanRepositoryProvider.future);
  final query = ref.watch(loanSearchQueryProvider);
  final statusFilter = ref.watch(loanStatusFilterProvider);
  final loanType = ref.watch(loanTypeFilterProvider);
  final result = await repo.getAllLoans(
      query: query, statusFilter: statusFilter, loanType: loanType);
  return result.when(success: (l) => l, failure: (f) => throw f);
});
