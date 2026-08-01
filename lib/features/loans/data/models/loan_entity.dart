import 'package:loantrack/core/utils/date_utils.dart';

enum LoanType { daily, weekly }

enum LoanStatus { active, completed, defaulted, pending, cancelled }

class Loan {
  final String id;
  final String customerId;
  final String? customerName;
  final LoanType loanType;
  final LoanStatus status;

  // Inputs from form
  final double amount;
  final double interestRate; // This is a percentage
  final double insuranceFee; // This is a percentage
  final double commission; // This is a percentage
  final double processingFee; // This is a flat amount
  final double administrativeFee; // This is a flat amount
  final double otherCharges; // This is a flat amount
  final int duration; // Days for daily, weeks for weekly
  final DateTime loanDate;
  final DateTime repaymentStartDate;

  // Calculated values to be stored
  final double totalRepayment;
  final double outstandingBalance;
  final double installmentAmount;
  final DateTime expectedCompletionDate;

  // Optional fields
  final String? notes;
  final double? customCollectionAmount;

  Loan({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.loanType,
    this.status = LoanStatus.active,
    required this.amount,
    required this.interestRate,
    this.insuranceFee = 0.0,
    this.commission = 0.0,
    this.processingFee = 0.0,
    this.administrativeFee = 0.0,
    this.otherCharges = 0.0,
    required this.duration,
    required this.loanDate,
    required this.repaymentStartDate,
    required this.totalRepayment,
    required this.outstandingBalance,
    required this.installmentAmount,
    required this.expectedCompletionDate,
    this.notes,
    this.customCollectionAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_id': customerId,
      'loan_type': loanType.name,
      'status': status.name,
      'amount': amount,
      'interest_rate': interestRate,
      'insurance_fee': insuranceFee,
      'commission': commission,
      'processing_fee': processingFee,
      'admin_fee': administrativeFee,
      'other_charges': otherCharges,
      'duration_days': loanType == LoanType.daily ? duration : null,
      'duration_weeks': loanType == LoanType.weekly ? duration : null,
      'repayment_frequency': loanType.name,
      'daily_payment': loanType == LoanType.daily ? installmentAmount : null,
      'weekly_payment': loanType == LoanType.weekly ? installmentAmount : null,
      'loan_date': AppDateUtils.formatForStorage(loanDate),
      'start_date': AppDateUtils.formatForStorage(repaymentStartDate),
      'total_repayment': totalRepayment,
      'outstanding_balance': outstandingBalance,
      'expected_completion_date':
          AppDateUtils.formatForStorage(expectedCompletionDate),
      'notes': notes,
      'custom_collection_amount': customCollectionAmount,
    };
  }

  Loan copyWith({
    String? id,
    String? customerId,
    String? customerName,
    LoanType? loanType,
    LoanStatus? status,
    double? amount,
    double? interestRate,
    double? insuranceFee,
    double? commission,
    double? processingFee,
    double? administrativeFee,
    double? otherCharges,
    int? duration,
    DateTime? loanDate,
    DateTime? repaymentStartDate,
    double? totalRepayment,
    double? outstandingBalance,
    double? installmentAmount,
    DateTime? expectedCompletionDate,
    String? notes,
    bool clearNotes = false,
    double? customCollectionAmount,
  }) {
    return Loan(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      loanType: loanType ?? this.loanType,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      interestRate: interestRate ?? this.interestRate,
      insuranceFee: insuranceFee ?? this.insuranceFee,
      commission: commission ?? this.commission,
      processingFee: processingFee ?? this.processingFee,
      administrativeFee: administrativeFee ?? this.administrativeFee,
      otherCharges: otherCharges ?? this.otherCharges,
      duration: duration ?? this.duration,
      loanDate: loanDate ?? this.loanDate,
      repaymentStartDate: repaymentStartDate ?? this.repaymentStartDate,
      totalRepayment: totalRepayment ?? this.totalRepayment,
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      installmentAmount: installmentAmount ?? this.installmentAmount,
      expectedCompletionDate: expectedCompletionDate ?? this.expectedCompletionDate,
      notes: clearNotes ? null : (notes ?? this.notes),
      customCollectionAmount: customCollectionAmount ?? this.customCollectionAmount,
    );
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    return Loan(
      id: map['id'] as String,
      customerId: map['customer_id'] as String,
      customerName: map['customer_name'] as String?,
      loanType: LoanType.values
          .firstWhere((e) => e.name == map['loan_type'], orElse: () => LoanType.daily),
      status: LoanStatus.values
          .firstWhere((e) => e.name == map['status'], orElse: () => LoanStatus.active),
      amount: (map['amount'] as num).toDouble(),
      interestRate: (map['interest_rate'] as num).toDouble(),
      insuranceFee: (map['insurance_fee'] as num?)?.toDouble() ?? 0.0,
      commission: (map['commission'] as num?)?.toDouble() ?? 0.0,
      processingFee: (map['processing_fee'] as num?)?.toDouble() ?? 0.0,
      administrativeFee: (map['admin_fee'] as num?)?.toDouble() ?? 0.0,
      otherCharges: (map['other_charges'] as num?)?.toDouble() ?? 0.0,
      duration: (((map['duration_days'] ?? map['duration_weeks']) as num?)?.toInt() ?? 1).clamp(1, 9999),
      loanDate: AppDateUtils.tryParseStorage(map['loan_date'] as String?) ?? DateTime.now(),
      repaymentStartDate:
          AppDateUtils.tryParseStorage(map['start_date'] as String?) ?? DateTime.now(),
      totalRepayment: (map['total_repayment'] as num).toDouble(),
      outstandingBalance: (map['outstanding_balance'] as num).toDouble(),
      installmentAmount:
          ((map['daily_payment'] ?? map['weekly_payment']) as num?)?.toDouble() ?? 0.0,
      expectedCompletionDate: AppDateUtils.tryParseStorage(
          map['expected_completion_date'] as String?) ?? DateTime.now(),
      notes: map['notes'] as String?,
      customCollectionAmount: (map['custom_collection_amount'] as num?)?.toDouble(),
    );
  }
}
