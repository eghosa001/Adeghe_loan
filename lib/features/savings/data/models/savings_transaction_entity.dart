enum SavingsTransactionType { deposit, withdrawal, overpayment }

extension SavingsTransactionTypeValue on SavingsTransactionType {
  String get value => name;

  static SavingsTransactionType fromValue(String? value) {
    return SavingsTransactionType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => SavingsTransactionType.deposit,
    );
  }
}

class SavingsTransaction {
  const SavingsTransaction({
    required this.id,
    required this.savingsAccountId,
    required this.type,
    required this.amount,
    this.referenceLoanPaymentId,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String savingsAccountId;
  final SavingsTransactionType type;
  final double amount;
  final String? referenceLoanPaymentId;
  final String? note;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'savings_account_id': savingsAccountId,
        'type': type.value,
        'amount': amount,
        'reference_loan_payment_id': referenceLoanPaymentId,
        'note': note,
        'created_at': createdAt,
      };

  factory SavingsTransaction.fromMap(Map<String, Object?> map) =>
      SavingsTransaction(
        id: map['id']! as String,
        savingsAccountId: map['savings_account_id']! as String,
        type: SavingsTransactionTypeValue.fromValue(map['type'] as String?),
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        referenceLoanPaymentId: map['reference_loan_payment_id'] as String?,
        note: map['note'] as String?,
        createdAt: map['created_at']! as String,
      );
}
