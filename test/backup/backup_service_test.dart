import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';
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
    final header = List<int>.generate(16, (i) => 0x41);
    expect(BackupService.isSqliteFile(header), isFalse);
  });

  test('LTBK2 is identified as an encrypted portable container', () {
    final bytes = <int>[0x4c, 0x54, 0x42, 0x4b, 0x32];
    expect(BackupService.isEncryptedContainer(bytes), isTrue);
    expect(BackupService.isPortableContainer(bytes), isTrue);
  });

  test('LTBK1 remains an encrypted legacy container but is not portable', () {
    final bytes = <int>[0x4c, 0x54, 0x42, 0x4b, 0x31];
    expect(BackupService.isEncryptedContainer(bytes), isTrue);
    expect(BackupService.isPortableContainer(bytes), isFalse);
  });

  test('portable backup key derivation is deterministic for the same password and salt', () {
    final salt = List<int>.generate(16, (i) => i + 1);
    final a = SecureStorageService.deriveBackupKey('CorrectHorseBattery123', salt: salt, iterations: 1000);
    final b = SecureStorageService.deriveBackupKey('CorrectHorseBattery123', salt: salt, iterations: 1000);
    expect(a, b);
    expect(base64Url.decode(a), hasLength(32));
  });

  test('portable backup key changes when password or salt changes', () {
    final salt = List<int>.generate(16, (i) => i + 1);
    final otherSalt = List<int>.generate(16, (i) => i + 2);
    final a = SecureStorageService.deriveBackupKey('CorrectHorseBattery123', salt: salt, iterations: 1000);
    final b = SecureStorageService.deriveBackupKey('WrongHorseBattery123', salt: salt, iterations: 1000);
    final c = SecureStorageService.deriveBackupKey('CorrectHorseBattery123', salt: otherSalt, iterations: 1000);
    expect(b, isNot(a));
    expect(c, isNot(a));
  });

  test('cached recovery-derived key produces the same portable backup key', () {
    const password = 'CorrectHorseBattery123';
    final salt = List<int>.generate(16, (i) => 255 - i);
    final derived = SecureStorageService.deriveDocumentKey(password, iterations: 1000);
    final fromPassword = SecureStorageService.deriveBackupKey(password, salt: salt, iterations: 1000);
    final fromDerived = SecureStorageService.deriveBackupKeyFromDerivedKey(derived, salt: salt);
    expect(fromDerived, fromPassword);
  });

  test('recovery password policy rejects weak passwords', () {
    expect(SecureStorageService.recoveryPasswordError('short1'), isNotNull);
    expect(SecureStorageService.recoveryPasswordError('abcdefghijklmnop'), isNotNull);
    expect(SecureStorageService.recoveryPasswordError('1234567890123456'), isNotNull);
    expect(SecureStorageService.recoveryPasswordError('CorrectHorseBattery123'), isNull);
  });
}
