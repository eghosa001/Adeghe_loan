import 'package:loantrack/core/utils/date_utils.dart';

enum PaymentMethod { cash, transfer, pos, cheque, mobileMoney, savings }

enum PaymentType { partial, full, overpayment }
enum PaymentStatus { completed, reversed }

class Payment {
  final String id;
  final String loanId;
  final String customerId;
  final double amount;
  final PaymentMethod method;
  final String? referenceNumber;
  final String receiptNumber;
  final DateTime paymentDate;
  final String collector;
  final PaymentType type;
  final PaymentStatus status;
  final String? remarks;
  final String? priorLoanStatus;
  final String? clientRequestId;
  final DateTime? createdAt;

  Payment({
    required this.id,
    required this.loanId,
    required this.customerId,
    required this.amount,
    required this.method,
    this.referenceNumber,
    required this.receiptNumber,
    required this.paymentDate,
    required this.collector,
    this.type = PaymentType.partial,
    this.status = PaymentStatus.completed,
    this.remarks,
    this.priorLoanStatus,
    this.clientRequestId,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'loan_id': loanId,
        'customer_id': customerId,
        'amount': amount,
        'payment_date': AppDateUtils.formatForStorage(paymentDate),
        'payment_method': method.name,
        'reference_no': referenceNumber,
        'receipt_no': receiptNumber,
        'collector': collector,
        'type': type.name,
        'remarks': remarks,
        'status': status.name,
        'prior_loan_status': priorLoanStatus,
        'client_request_id': clientRequestId,
        'created_at': createdAt?.toIso8601String(),
      };

  factory Payment.fromMap(Map<String, Object?> map) {
    final amountValue = map['amount'];
    if (amountValue is! num || !amountValue.isFinite || amountValue <= 0) {
      throw FormatException('Payment amount is invalid.');
    }

    final paymentDate = AppDateUtils.tryParseStorage(map['payment_date'] as String?);
    if (paymentDate == null) {
      throw FormatException('Payment date is invalid.');
    }

    DateTime? createdAt;
    final rawCreatedAt = map['created_at'];
    if (rawCreatedAt != null) {
      if (rawCreatedAt is! String) {
        throw FormatException('Payment created_at is invalid.');
      }
      createdAt = DateTime.tryParse(rawCreatedAt);
      if (createdAt == null) {
        throw FormatException('Payment created_at is invalid.');
      }
    }

    return Payment(
      id: _requiredString(map, 'id'),
      loanId: _requiredString(map, 'loan_id'),
      customerId: _requiredString(map, 'customer_id'),
      amount: amountValue.toDouble(),
      paymentDate: paymentDate,
      method: _enumValue(PaymentMethod.values, map['payment_method'], 'payment_method'),
      referenceNumber: map['reference_no'] as String?,
      receiptNumber: _requiredString(map, 'receipt_no'),
      collector: _requiredString(map, 'collector'),
      type: _enumValue(PaymentType.values, map['type'] ?? PaymentType.partial.name, 'type'),
      status: _enumValue(
        PaymentStatus.values,
        map['status'] ?? PaymentStatus.completed.name,
        'status',
      ),
      remarks: map['remarks'] as String?,
      priorLoanStatus: map['prior_loan_status'] as String?,
      clientRequestId: map['client_request_id'] as String?,
      createdAt: createdAt,
    );
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Payment $key is missing or invalid.');
    }
    return value;
  }

  static T _enumValue<T extends Enum>(List<T> values, Object? raw, String field) {
    if (raw is String) {
      for (final value in values) {
        if (value.name == raw) return value;
      }
    }
    throw FormatException('Payment $field contains an unknown value.');
  }
}
