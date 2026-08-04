import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/security/secure_storage_service.dart';

/// Guards the API-6 document-key derivation contract: the key used to encrypt
/// customer documents is derived deterministically from the recovery password,
/// so the same recovery password entered on a second device decrypts the same
/// cloud-synced files. The salt must be fixed (never per-device) for that to
/// hold. Iterations are lowered in tests to keep the suite fast; the derivation
/// output is identical in structure to the production 600k run.
void main() {
  group('SecureStorageService.deriveDocumentKey', () {
    test('is deterministic: the same password always yields the same key', () {
      const password = 'MyRecoveryPassword123';
      expect(
        SecureStorageService.deriveDocumentKey(password, iterations: 1000),
        SecureStorageService.deriveDocumentKey(password, iterations: 1000),
      );
    });

    test('different passwords yield different keys', () {
      final a = SecureStorageService.deriveDocumentKey('PasswordOne12345',
          iterations: 1000);
      final b = SecureStorageService.deriveDocumentKey('PasswordTwo12345',
          iterations: 1000);
      expect(a, isNot(b));
    });

    test('salt is fixed and known, enabling cross-device derivation', () {
      expect(SecureStorageService.docDerivationSalt, 'loantrack-doc-key-v1');
      // Two independent calls (two devices) derive the same key with no shared
      // per-device state — only the password matters.
      expect(
        SecureStorageService.deriveDocumentKey('SharedRecovery!42',
            iterations: 1000),
        SecureStorageService.deriveDocumentKey('SharedRecovery!42',
            iterations: 1000),
      );
    });

    test('derived key is a base64 32-byte value (AES-256 key material)', () {
      final key = SecureStorageService.deriveDocumentKey('AnotherPass12345',
          iterations: 1000);
      expect(key.length, greaterThanOrEqualTo(40));
      expect(key.length, lessThanOrEqualTo(48));
    });
  });
}
