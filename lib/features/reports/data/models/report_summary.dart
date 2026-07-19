class ReportSummary {
  ReportSummary({
    required this.totalDisbursed,
    required this.totalCollected,
    required this.netProfit,
    required this.activeLoans,
    required this.completedLoans,
    required this.defaultedLoans,
  });

  final double totalDisbursed;
  final double totalCollected;
  final double netProfit;
  final int activeLoans;
  final int completedLoans;
  final int defaultedLoans;
}
