import 'package:loantrack/core/utils/currency_utils.dart';

/// The output of a loan calculation, containing all the key financial metrics.
class LoanCalculationResult {
  /// The principal amount of the loan.
  final double principal;

  /// The calculated flat interest amount.
  final double interestAmount;

  /// The calculated insurance fee amount.
  final double insuranceFeeAmount;

  /// The calculated commission amount.
  final double commissionAmount;

  /// The sum of all non-interest charges (insurance, commission, processing, etc.).
  final double totalCharges;

  /// The total amount the borrower must repay (principal + interest + charges).
  final double totalRepayment;

  /// The daily installment amount.
  final double installmentAmount;

  LoanCalculationResult({
    required this.principal,
    required this.interestAmount,
    required this.insuranceFeeAmount,
    required this.commissionAmount,
    required this.totalCharges,
    required this.totalRepayment,
    required this.installmentAmount,
  });
}

/// A pure-logic service for calculating loan metrics based on flat-rate microfinance rules.
class LoanCalculator {
  LoanCalculator._();

  /// Calculates all key financial metrics for a new loan.
  ///
  /// This uses a flat-rate calculation method, where interest and percentage-based
  /// fees are calculated once on the initial principal amount.
  static LoanCalculationResult calculate({
    required double principal,
    required double interestRatePercent,
    required double insuranceFeePercent,
    required double commissionPercent,
    required double processingFee,
    required double administrativeFee,
    required double otherCharges,
    required int duration, // In days
  }) {
    if (principal <= 0 || duration <= 0) {
      return LoanCalculationResult(
        principal: principal,
        interestAmount: 0,
        insuranceFeeAmount: 0,
        commissionAmount: 0,
        totalCharges: 0,
        totalRepayment: principal,
        installmentAmount: 0,
      );
    }

    final interestAmount = principal * (interestRatePercent / 100);
    final insuranceFeeAmount = principal * (insuranceFeePercent / 100);
    final commissionAmount = principal * (commissionPercent / 100);
    final totalCharges = insuranceFeeAmount + commissionAmount + processingFee + administrativeFee + otherCharges;
    final totalRepayment = principal + interestAmount + totalCharges;
    final installmentAmount = totalRepayment / duration;

    return LoanCalculationResult(
      principal: principal,
      interestAmount: CurrencyUtils.roundToCents(interestAmount),
      insuranceFeeAmount: CurrencyUtils.roundToCents(insuranceFeeAmount),
      commissionAmount: CurrencyUtils.roundToCents(commissionAmount),
      totalCharges: CurrencyUtils.roundToCents(totalCharges),
      totalRepayment: CurrencyUtils.roundToCents(totalRepayment),
      installmentAmount: CurrencyUtils.roundToCents(installmentAmount),
    );
  }
}
