class AuditLog {
  AuditLog({
    required this.id,
    required this.user,
    required this.action,
    required this.timestamp,
    required this.details,
  });

  final String id;
  final String user;
  final String action;
  final DateTime timestamp;
  final String details;

  Map<String, dynamic> toMap() => {
        'id': id,
        'user': user,
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        'details': details,
      };

  factory AuditLog.fromMap(Map<String, dynamic> map) => AuditLog(
        id: map['id'] as String,
        user: map['user'] as String,
        action: map['action'] as String,
        timestamp: DateTime.tryParse(map['timestamp'] as String) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        details: map['details'] as String,
      );
}
