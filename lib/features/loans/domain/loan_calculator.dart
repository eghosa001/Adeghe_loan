import 'package:loantrack/core/utils/currency_utils.dart';

/// The output of a loan calculation, containing all the key financial metrics.
class LoanCalculationResult {
  final double principal;
  final double interestAmount;
  final double insuranceFeeAmount;
  final double commissionAmount;
  final double totalCharges;
  final double totalRepayment;
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

/// Pure-logic service for flat-rate microfinance loan calculations.
class LoanCalculator {
  LoanCalculator._();

  static LoanCalculationResult calculate({
    required double principal,
    required double interestRatePercent,
    required double insuranceFeePercent,
    required double commissionPercent,
    required double processingFee,
    required double administrativeFee,
    required double otherCharges,
    required int duration,
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

    final principalCents = CurrencyUtils.toMinorUnits(principal);
    int percentOfPrincipal(double percent) =>
        (principalCents * percent / 100).round();

    final interestCents = percentOfPrincipal(interestRatePercent);
    final insuranceCents = percentOfPrincipal(insuranceFeePercent);
    final commissionCents = percentOfPrincipal(commissionPercent);
    final chargesCents = insuranceCents +
        commissionCents +
        CurrencyUtils.toMinorUnits(processingFee) +
        CurrencyUtils.toMinorUnits(administrativeFee) +
        CurrencyUtils.toMinorUnits(otherCharges);
    final totalCents = principalCents + interestCents + chargesCents;
    final installmentCents = totalCents ~/ duration;

    return LoanCalculationResult(
      principal: CurrencyUtils.fromMinorUnits(principalCents),
      interestAmount: CurrencyUtils.fromMinorUnits(interestCents),
      insuranceFeeAmount: CurrencyUtils.fromMinorUnits(insuranceCents),
      commissionAmount: CurrencyUtils.fromMinorUnits(commissionCents),
      totalCharges: CurrencyUtils.fromMinorUnits(chargesCents),
      totalRepayment: CurrencyUtils.fromMinorUnits(totalCents),
      installmentAmount: CurrencyUtils.fromMinorUnits(installmentCents),
    );
  }
}
