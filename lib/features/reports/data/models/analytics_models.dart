class PortfolioBreakdown {
  PortfolioBreakdown({
    required this.activeCount,
    required this.completedCount,
    required this.defaultedCount,
    required this.activeAmount,
    required this.completedAmount,
    required this.defaultedAmount,
  });

  final int activeCount;
  final int completedCount;
  final int defaultedCount;
  final double activeAmount;
  final double completedAmount;
  final double defaultedAmount;

  int get totalCount => activeCount + completedCount + defaultedCount;
  double get totalAmount => activeAmount + completedAmount + defaultedAmount;
}

class MonthlyTrendPoint {
  MonthlyTrendPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class CollectionTrend {
  CollectionTrend({
    required this.label,
    required this.expected,
    required this.collected,
    required this.efficiency,
  });
  final String label;
  final double expected;
  final double collected;
  final double efficiency;
}

class GrowthStats {
  GrowthStats({
    required this.totalCustomers,
    required this.activeCustomers,
    required this.inactiveCustomers,
    required this.repeatBorrowers,
    required this.newCustomersThisMonth,
    required this.customerGrowth,
    required this.loanGrowth,
  });

  final int totalCustomers;
  final int activeCustomers;
  final int inactiveCustomers;
  final int repeatBorrowers;
  final int newCustomersThisMonth;
  final List<MonthlyTrendPoint> customerGrowth;
  final List<MonthlyTrendPoint> loanGrowth;
}

class SavingsTrendPoint {
  SavingsTrendPoint({
    required this.label,
    required this.deposits,
    required this.withdrawals,
    required this.balance,
  });
  final String label;
  final double deposits;
  final double withdrawals;
  final double balance;
}
