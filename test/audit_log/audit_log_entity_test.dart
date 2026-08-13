import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/audit_log/data/models/audit_log_entity.dart';

void main() {
  test('audit log mapping preserves its fields', () {
    final log = AuditLog(
      id: 'A1',
      user: 'admin',
      action: 'create_loan',
      timestamp: DateTime.utc(2026, 8, 12),
      details: 'details',
    );

    final restored = AuditLog.fromMap(log.toMap());

    expect(restored.id, log.id);
    expect(restored.user, log.user);
    expect(restored.action, log.action);
    expect(restored.timestamp, log.timestamp);
    expect(restored.details, log.details);
  });

  test(
      'audit log mapping falls back to the epoch for a malformed timestamp '
      '(tamper guard)', () {
    final restored = AuditLog.fromMap({
      'id': 'A1',
      'user': 'admin',
      'action': 'create_loan',
      'timestamp': 'garbage',
      'details': 'details',
    });

    expect(restored.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
  });
}
