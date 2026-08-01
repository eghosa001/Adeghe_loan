class FinancialSettings {
  final String currency;
  final double defaultInterestRate;
  final double defaultInsuranceFee;
  final double defaultCommission;
  final double defaultProcessingFee;
  final String defaultPenaltyRules;
  final int defaultLoanDurationDays;
  final String defaultLoanType;

  FinancialSettings({
    this.currency = '₦',
    this.defaultInterestRate = 0.0,
    this.defaultInsuranceFee = 0.0,
    this.defaultCommission = 0.0,
    this.defaultProcessingFee = 0.0,
    this.defaultPenaltyRules = '',
    this.defaultLoanDurationDays = 30,
    this.defaultLoanType = 'daily',
  });
}
