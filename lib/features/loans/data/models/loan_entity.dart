import 'package:loantrack/core/utils/date_utils.dart';

enum LoanType { daily, weekly }

enum LoanStatus { active, completed, defaulted, pending, cancelled }

class Loan {
  final String id;
  final String customerId;
  final String? customerName;
  final LoanType loanType;
  final LoanStatus status;
  final double amount;
  final double interestRate;
  final double insuranceFee;
  final double commission;
  final double processingFee;
  final double administrativeFee;
  final double otherCharges;
  final int duration;
  final DateTime loanDate;
  final DateTime repaymentStartDate;
  final double totalRepayment;
  final double outstandingBalance;
  final double installmentAmount;
  final DateTime expectedCompletionDate;
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
      expectedCompletionDate:
          expectedCompletionDate ?? this.expectedCompletionDate,
      notes: clearNotes ? null : (notes ?? this.notes),
      customCollectionAmount:
          customCollectionAmount ?? this.customCollectionAmount,
    );
  }

  factory Loan.fromMap(Map<String, dynamic> map) {
    final id = _requiredString(map, 'id');
    final customerId = _requiredString(map, 'customer_id');
    final loanType = _enumValue(LoanType.values, map['loan_type'], 'loan_type');
    final status = _enumValue(LoanStatus.values, map['status'], 'status');

    final amount = _finiteNumber(map, 'amount');
    final interestRate = _finiteNumber(map, 'interest_rate');
    final insuranceFee = _optionalFiniteNumber(map, 'insurance_fee') ?? 0.0;
    final commission = _optionalFiniteNumber(map, 'commission') ?? 0.0;
    final processingFee = _optionalFiniteNumber(map, 'processing_fee') ?? 0.0;
    final administrativeFee = _optionalFiniteNumber(map, 'admin_fee') ?? 0.0;
    final otherCharges = _optionalFiniteNumber(map, 'other_charges') ?? 0.0;
    final totalRepayment = _finiteNumber(map, 'total_repayment');
    final outstandingBalance = _finiteNumber(map, 'outstanding_balance');
    final installmentAmount = _optionalFiniteNumber(
          map, loanType == LoanType.daily ? 'daily_payment' : 'weekly_payment') ??
        0.0;

    final rawDuration =
        loanType == LoanType.daily ? map['duration_days'] : map['duration_weeks'];
    if (rawDuration is! int || rawDuration <= 0) {
      throw FormatException('Loan duration is missing or invalid.');
    }

    final loanDate = _requiredDate(map, 'loan_date');
    final repaymentStartDate = _requiredDate(map, 'start_date');
    final expectedCompletionDate =
        _requiredDate(map, 'expected_completion_date');

    final customCollectionAmount =
        _optionalFiniteNumber(map, 'custom_collection_amount');
    if (customCollectionAmount != null && customCollectionAmount <= 0) {
      throw FormatException('Loan custom_collection_amount is invalid.');
    }

    for (final entry in {
      'amount': amount,
      'interest_rate': interestRate,
      'insurance_fee': insuranceFee,
      'commission': commission,
      'processing_fee': processingFee,
      'admin_fee': administrativeFee,
      'other_charges': otherCharges,
      'total_repayment': totalRepayment,
      'outstanding_balance': outstandingBalance,
      'installment_amount': installmentAmount,
    }.entries) {
      if (entry.value < 0) {
        throw FormatException('Loan ${entry.key} cannot be negative.');
      }
    }
    if (totalRepayment <= 0) {
      throw FormatException('Loan total_repayment must be positive.');
    }
    if (totalRepayment < amount) {
      throw FormatException(
          'Loan total_repayment cannot be less than the amount disbursed.');
    }
    if (outstandingBalance > totalRepayment) {
      throw FormatException(
          'Loan outstanding_balance cannot exceed total_repayment.');
    }

    return Loan(
      id: id,
      customerId: customerId,
      customerName: map['customer_name'] as String?,
      loanType: loanType,
      status: status,
      amount: amount,
      interestRate: interestRate,
      insuranceFee: insuranceFee,
      commission: commission,
      processingFee: processingFee,
      administrativeFee: administrativeFee,
      otherCharges: otherCharges,
      duration: rawDuration,
      loanDate: loanDate,
      repaymentStartDate: repaymentStartDate,
      totalRepayment: totalRepayment,
      outstandingBalance: outstandingBalance,
      installmentAmount: installmentAmount,
      expectedCompletionDate: expectedCompletionDate,
      notes: map['notes'] as String?,
      customCollectionAmount: customCollectionAmount,
    );
  }

  static String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Loan $key is missing or invalid.');
    }
    return value;
  }

  static double _finiteNumber(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('Loan $key is missing or invalid.');
    }
    return value.toDouble();
  }

  static double? _optionalFiniteNumber(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite) {
      throw FormatException('Loan $key is invalid.');
    }
    return value.toDouble();
  }

  static DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final raw = map[key];
    if (raw is! String) {
      throw FormatException('Loan $key is missing or invalid.');
    }
    final parsed = AppDateUtils.tryParseStorage(raw);
    if (parsed == null) {
      throw FormatException('Loan $key is invalid.');
    }
    return parsed;
  }

  static T _enumValue<T extends Enum>(
      List<T> values, Object? raw, String field) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    throw FormatException('Loan $field contains an unknown value.');
  }
}
