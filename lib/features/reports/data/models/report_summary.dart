class LoanTypeReportSummary {
  const LoanTypeReportSummary({
    required this.activeLoans,
    required this.completedLoans,
    required this.overdueLoans,
    required this.defaultedLoans,
    required this.amountDisbursed,
    required this.outstandingBalance,
    required this.amountCollected,
    required this.expectedCollections,
    required this.collectionEfficiency,
    required this.interestEarned,
    required this.feesEarned,
    required this.savingsFromOverpayments,
    required this.customerCount,
    this.clientReports = const [],
    this.overdueEntries = const [],
  });

  /// Zeroed summary used when a loan-type filter excludes this bucket, so
  /// combined totals are never skewed by the skipped type.
  const LoanTypeReportSummary.empty()
      : activeLoans = 0,
        completedLoans = 0,
        overdueLoans = 0,
        defaultedLoans = 0,
        amountDisbursed = 0,
        outstandingBalance = 0,
        amountCollected = 0,
        expectedCollections = 0,
        collectionEfficiency = 0,
        interestEarned = 0,
        feesEarned = 0,
        savingsFromOverpayments = 0,
        customerCount = 0,
        clientReports = const [],
        overdueEntries = const [];

  final int activeLoans;
  final int completedLoans;
  final int overdueLoans;
  final int defaultedLoans;
  final double amountDisbursed;
  final double outstandingBalance;
  final double amountCollected;
  final double expectedCollections;
  final double collectionEfficiency;
  final double interestEarned;
  final double feesEarned;
  final double savingsFromOverpayments;
  final int customerCount;
  final List<ClientReport> clientReports;
  final List<OverdueEntry> overdueEntries;
}

class ReportSummary {
  const ReportSummary({
    required this.dailyLoans,
    required this.weeklyLoans,
    required this.totalDisbursed,
    required this.totalCollected,
    required this.netProfit,
    required this.activeLoans,
    required this.completedLoans,
    required this.defaultedLoans,
    required this.totalCustomers,
    this.clientReports = const [],
    this.overdueEntries = const [],
  });

  final LoanTypeReportSummary dailyLoans;
  final LoanTypeReportSummary weeklyLoans;
  final double totalDisbursed;
  final double totalCollected;
  final double netProfit;
  final int activeLoans;
  final int completedLoans;
  final int defaultedLoans;
  final int totalCustomers;
  final List<ClientReport> clientReports;
  final List<OverdueEntry> overdueEntries;
}

class ClientReport {
  ClientReport({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.loanType,
    required this.loanId,
    required this.amountBorrowed,
    required this.outstandingBalance,
    required this.totalPaid,
    required this.loanStatus,
    this.groupName,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String loanType;
  final String loanId;
  final double amountBorrowed;
  final double outstandingBalance;
  final double totalPaid;
  final String loanStatus;
  final String? groupName;
}

class OverdueEntry {
  OverdueEntry({
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.loanId,
    required this.loanType,
    required this.installmentNumber,
    required this.dueDate,
    required this.amountDue,
    required this.paidAmount,
    required this.overdueDays,
    this.groupName,
  });

  final String customerId;
  final String customerName;
  final String phone;
  final String loanId;
  final String loanType;
  final int installmentNumber;
  final String dueDate;
  final double amountDue;
  final double paidAmount;
  final int overdueDays;
  final String? groupName;

  double get amountRemaining => (amountDue - paidAmount).clamp(0.0, double.infinity);
}
