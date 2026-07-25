import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/features/customers/presentation/providers/customer_providers.dart';
import 'package:loantrack/features/dashboard/presentation/providers/dashboard_provider.dart';
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
    );
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
    int? duration,
    DateTime? repaymentStartDate,
  }) {
    state = state.copyWith(
      loanType: loanType,
      principal: principal,
      interestRatePercent: interestRatePercent,
      duration: duration,
      repaymentStartDate: repaymentStartDate,
    );
    _recalculate();
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

  Future<void> saveLoan(String customerId) async {
    if (state.calculationResult == null || state.duration <= 0) {
      throw Exception("Cannot save loan with invalid data.");
    }

    final holidays = await _ref.read(holidayListProvider.future);
    final loanRepo = await _ref.read(loanRepositoryProvider.future);
    final loanId = 'L-${DateTime.now().microsecondsSinceEpoch}';

    final schedule = ScheduleGenerator.generate(
      loanId: loanId,
      loanType: state.loanType,
      startDate: state.repaymentStartDate,
      duration: state.duration,
      installmentAmount: state.calculationResult!.installmentAmount,
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
        duration: state.duration,
        loanDate: DateTime.now(),
        repaymentStartDate: state.repaymentStartDate,
        totalRepayment: state.calculationResult!.totalRepayment,
        outstandingBalance: state.calculationResult!.totalRepayment,
        installmentAmount: state.calculationResult!.installmentAmount,
        expectedCompletionDate: schedule.last.dueDate);

    final result = await loanRepo.saveLoanAndSchedule(loan, schedule);
    result.when(
      success: (_) {
        _ref.invalidate(dashboardDataProvider);
        _ref.invalidate(customerListProvider);
        _ref.invalidate(customerProvider(customerId));
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
