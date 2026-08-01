import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/security/pin_lockout_service.dart';
import 'package:loantrack/core/security/secure_key_value_store.dart';

class InMemoryStore implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  InMemoryStore copy() => InMemoryStore().._data.addAll(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);
}

void main() {
  late InMemoryStore store;
  late PinLockoutService service;

  setUp(() {
    store = InMemoryStore();
    service = PinLockoutService(store);
  });

  test('starts with no lockout', () async {
    expect(await service.isLockedOut(), isFalse);
    expect(await service.remainingLockout(), isNull);
  });

  test('locks out after maxAttempts failures and persists across instances',
      () async {
    for (var i = 0; i < service.maxAttempts - 1; i++) {
      expect(await service.registerFailedAttempt(), isFalse);
      expect(await service.isLockedOut(), isFalse);
    }
    final triggered = await service.registerFailedAttempt();
    expect(triggered, isTrue);
    expect(await service.isLockedOut(), isTrue);

    // A brand-new service instance still sees the lockout (persisted state).
    final secondService = PinLockoutService(store.copy());
    expect(await secondService.isLockedOut(), isTrue);
  });

  test('reset clears lockout and attempts', () async {
    for (var i = 0; i < service.maxAttempts; i++) {
      await service.registerFailedAttempt();
    }
    expect(await service.isLockedOut(), isTrue);

    await service.reset();
    expect(await service.isLockedOut(), isFalse);
    expect(await service.remainingLockout(), isNull);

    // Counter reset too: next failure is the first again.
    await service.registerFailedAttempt();
    expect(await service.isLockedOut(), isFalse);
  });

  test('remainingLockout returns a positive duration while locked', () async {
    for (var i = 0; i < service.maxAttempts; i++) {
      await service.registerFailedAttempt();
    }
    final remaining = await service.remainingLockout();
    expect(remaining, isNotNull);
    expect(remaining!.inSeconds, greaterThan(0));
  });
}
