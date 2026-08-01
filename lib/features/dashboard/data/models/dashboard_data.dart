import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

class DashboardData {
  DashboardData({
    required this.totalCustomers,
    required this.activeLoans,
    required this.dailyActiveLoans,
    required this.weeklyActiveLoans,
    required this.totalDisbursed,
    required this.dailyDisbursed,
    required this.weeklyDisbursed,
    required this.totalCollected,
    required this.dailyCollected,
    required this.weeklyCollected,
    required this.outstandingBalance,
    required this.dailyOutstandingBalance,
    required this.weeklyOutstandingBalance,
    required this.recentLoans,
    required this.recentPayments,
    this.totalSavingsBalance = 0.0,
    this.totalGroups = 0,
    this.recentSavingsTransactions = const [],
  });

  final int totalCustomers;
  final int activeLoans;
  final int dailyActiveLoans;
  final int weeklyActiveLoans;
  final double totalDisbursed;
  final double dailyDisbursed;
  final double weeklyDisbursed;
  final double totalCollected;
  final double dailyCollected;
  final double weeklyCollected;
  final double outstandingBalance;
  final double dailyOutstandingBalance;
  final double weeklyOutstandingBalance;
  final double totalSavingsBalance;
  final int totalGroups;
  final List<Loan> recentLoans;
  final List<Payment> recentPayments;
  final List<DashboardSavingsTransaction> recentSavingsTransactions;
}

class DashboardSavingsTransaction {
  DashboardSavingsTransaction({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.type,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String type;
  final double amount;
  final String createdAt;

  bool get isCredit => type == 'deposit';
  bool get isDebit => type == 'withdrawal';

  factory DashboardSavingsTransaction.fromMap(Map<String, dynamic> row) {
    return DashboardSavingsTransaction(
      id: row['id'] as String? ?? '',
      customerId: row['customerId'] as String? ?? '',
      customerName: row['customerName'] as String? ?? '',
      type: row['type'] as String? ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
      createdAt: row['createdAt'] as String? ?? '',
    );
  }
}
