import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/backup/data/backup_service.dart';

void main() {
  test('isSqliteFile accepts the real SQLite format magic', () {
    final header = utf8.encode('SQLite format 3\u0000');
    expect(BackupService.isSqliteFile(header), isTrue);
  });

  test('isSqliteFile rejects short headers', () {
    expect(BackupService.isSqliteFile(utf8.encode('SQLite')), isFalse);
    expect(BackupService.isSqliteFile(const <int>[]), isFalse);
  });

  test('isSqliteFile rejects non-SQLite file content', () {
    final header = List<int>.generate(16, (i) => 0x41); // 'AAAA...'
    expect(BackupService.isSqliteFile(header), isFalse);
  });
}
