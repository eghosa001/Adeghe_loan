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
