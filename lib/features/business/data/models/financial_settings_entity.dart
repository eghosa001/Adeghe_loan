class FinancialSettings {
  final String currency;
  final double defaultInterestRate;
  final double defaultInsuranceFee;
  final double defaultCommission;
  final double defaultProcessingFee;
  final String defaultPenaltyRules;
  final int defaultLoanDurationDays;
  final String defaultLoanType;

  /// Whether the operator has actually saved any loan-default values into the
  /// settings table (interest/duration/type/fees). A fresh install has an
  /// empty settings table, so the loan form must keep its built-in per-type
  /// defaults instead of applying the 0%/30-day placeholders returned by the
  /// entity constructor.
  final bool hasStoredLoanDefaults;

  FinancialSettings({
    this.currency = '₦',
    this.defaultInterestRate = 0.0,
    this.defaultInsuranceFee = 0.0,
    this.defaultCommission = 0.0,
    this.defaultProcessingFee = 0.0,
    this.defaultPenaltyRules = '',
    this.defaultLoanDurationDays = 30,
    this.defaultLoanType = 'daily',
    this.hasStoredLoanDefaults = false,
  });
}
