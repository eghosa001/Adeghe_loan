enum SavingsTransactionType { deposit, withdrawal, overpayment }

extension SavingsTransactionTypeValue on SavingsTransactionType {
  String get value => name;
  static SavingsTransactionType fromValue(String? v) =>
      SavingsTransactionType.values.firstWhere(
        (e) => e.value == v,
        orElse: () => SavingsTransactionType.deposit,
      );
}

class SavingsAccount {
  const SavingsAccount({
    required this.id,
    required this.customerId,
    required this.balance,
    required this.createdAt,
  });

  final String id;
  final String customerId;
  final double balance;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'customer_id': customerId,
        'balance': balance,
        'created_at': createdAt,
      };

  factory SavingsAccount.fromMap(Map<String, Object?> map) => SavingsAccount(
        id: map['id']! as String,
        customerId: map['customer_id']! as String,
        balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
        createdAt: map['created_at']! as String,
      );
}

class SavingsTransaction {
  const SavingsTransaction({
    required this.id,
    required this.savingsAccountId,
    required this.type,
    required this.amount,
    required this.note,
    required this.createdAt,
    this.referenceLoanPaymentId,
  });

  final String id;
  final String savingsAccountId;
  final SavingsTransactionType type;
  final double amount;
  final String note;
  final String createdAt;
  final String? referenceLoanPaymentId;

  Map<String, Object?> toMap() => {
        'id': id,
        'savings_account_id': savingsAccountId,
        'type': type.value,
        'amount': amount,
        'note': note,
        'created_at': createdAt,
        'reference_loan_payment_id': referenceLoanPaymentId,
      };

  factory SavingsTransaction.fromMap(Map<String, Object?> map) =>
      SavingsTransaction(
        id: map['id']! as String,
        savingsAccountId: map['savings_account_id']! as String,
        type: SavingsTransactionTypeValue.fromValue(map['type'] as String?),
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        note: map['note'] as String? ?? '',
        createdAt: map['created_at']! as String,
        referenceLoanPaymentId: map['reference_loan_payment_id'] as String?,
      );
}
