import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/core/security/pin_lockout_service.dart';
import 'package:loantrack/core/security/secure_key_value_store.dart';

class _MemoryStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  test('five failures start an escalating lockout', () async {
    final store = _MemoryStore();
    final service = PinLockoutService(store);

    for (var i = 0; i < AppConstants.maxPinAttempts - 1; i++) {
      expect(await service.registerFailedAttempt(), isFalse);
    }
    expect(await service.registerFailedAttempt(), isTrue);
    expect(await service.isLockedOut(), isTrue);
    expect(store.values[AppConstants.keyLockoutStarted], isNotNull);
    expect(store.values[AppConstants.keyLockoutUntil], isNotNull);
  });

  test('lockout state is cleared by reset', () async {
    final store = _MemoryStore();
    final service = PinLockoutService(store);

    for (var i = 0; i < AppConstants.maxPinAttempts; i++) {
      await service.registerFailedAttempt();
    }
    await service.reset();

    expect(await service.isLockedOut(), isFalse);
    expect(store.values[AppConstants.keyLockoutStarted], isNull);
    expect(store.values[AppConstants.keyLockoutUntil], isNull);
  });

  test('concurrent failures are serialized and cannot lose attempts', () async {
    final store = _MemoryStore();
    final service = PinLockoutService(store);

    final results = await Future.wait(
      List.generate(5, (_) => service.registerFailedAttempt()),
    );

    expect(results.where((locked) => locked).length, 1);
    expect(await service.isLockedOut(), isTrue);
  });

  test('corrupt lockout state fails closed instead of unlocking', () async {
    final store = _MemoryStore();
    store.values[AppConstants.keyLockoutUntil] = 'not-a-date';
    store.values[AppConstants.keyLockoutStarted] = 'not-a-date';
    final service = PinLockoutService(store);

    expect(await service.isLockedOut(), isTrue);
    expect(await service.isPermanentlyLocked(), isTrue);
  });

  test('incomplete lockout state fails closed', () async {
    final store = _MemoryStore();
    store.values[AppConstants.keyLockoutUntil] =
        DateTime.now().add(const Duration(minutes: 5)).toIso8601String();
    final service = PinLockoutService(store);

    expect(await service.isLockedOut(), isTrue);
    expect(await service.isPermanentlyLocked(), isTrue);
  });
}
