import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/payments/data/models/payment_entity.dart';

class DashboardData {
  DashboardData({
    required this.totalCustomers,
    required this.activeLoans,
    required this.dailyActiveLoans,
    required this.weeklyActiveLoans,
    required this.totalDisbursed,
    required this.totalCollected,
    required this.dailyCollected,
    required this.weeklyCollected,
    required this.outstandingBalance,
    required this.dailyOutstandingBalance,
    required this.weeklyOutstandingBalance,
    required this.recentLoans,
    required this.recentPayments,
  });

  final int totalCustomers;
  final int activeLoans;
  final int dailyActiveLoans;
  final int weeklyActiveLoans;
  final double totalDisbursed;
  final double totalCollected;
  /// Payments received today (completed status).
  final double dailyCollected;
  /// Payments received in the last 7 days (completed status).
  final double weeklyCollected;
  final double outstandingBalance;
  /// Installments due today that have not been fully paid (from repayment_schedule).
  final double dailyOutstandingBalance;
  /// Installments due in the last 7 days that have not been fully paid.
  final double weeklyOutstandingBalance;
  final List<Loan> recentLoans;
  final List<Payment> recentPayments;
}
