import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';

void main() {
  test('generateDatabaseKey produces a 32-byte base64url-decodable value', () {
    final rnd = Random(42);
    final key = SecureStorageService.generateDatabaseKey(rnd: rnd);
    // Ensure it decodes and is 32 bytes
    final decoded = base64Url.decode(key);
    expect(decoded.length, 32);
  });
}
