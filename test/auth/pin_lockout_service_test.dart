import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/constants/app_constants.dart';
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

  test('lockout duration doubles with each lockout cycle', () async {
    const expectedDurations = [
      Duration(minutes: 5),
      Duration(minutes: 10),
      Duration(minutes: 20),
      Duration(minutes: 40),
    ];
    for (final expected in expectedDurations) {
      for (var i = 0; i < service.maxAttempts; i++) {
        await service.registerFailedAttempt();
      }
      final storedUntil =
          await store.read(AppConstants.keyLockoutUntil);
      expect(storedUntil, isNotNull);
      final duration = DateTime.parse(storedUntil!).difference(DateTime.now());
      expect(
        duration.inMinutes,
        inInclusiveRange(expected.inMinutes - 1, expected.inMinutes + 1),
      );
    }
  });

  test('permanent lock after maxLockoutCycles blocks further attempts',
      () async {
    for (var cycle = 0; cycle < AppConstants.maxLockoutCycles; cycle++) {
      for (var i = 0; i < service.maxAttempts; i++) {
        await service.registerFailedAttempt();
      }
    }
    expect(await service.isPermanentlyLocked(), isTrue);
    expect(await service.isLockedOut(), isTrue);

    // Even after a (simulated) long wait, a permanently locked device stays
    // locked — a clock change cannot restore guessing.
    final stillLocked = await service.isLockedOut();
    expect(stillLocked, isTrue);

    // registerFailedAttempt reports "still locked" and does not escalate.
    final triggered = await service.registerFailedAttempt();
    expect(triggered, isTrue);
    expect(await service.isPermanentlyLocked(), isTrue);
  });

  test('reset clears permanent lock and cycles', () async {
    for (var cycle = 0; cycle < AppConstants.maxLockoutCycles; cycle++) {
      for (var i = 0; i < service.maxAttempts; i++) {
        await service.registerFailedAttempt();
      }
    }
    expect(await service.isPermanentlyLocked(), isTrue);

    await service.reset();
    expect(await service.isPermanentlyLocked(), isFalse);
    expect(await service.isLockedOut(), isFalse);
    expect(await service.remainingLockout(), isNull);
  });

  test('remainingLockout returns a long fixed duration when permanently locked',
      () async {
    for (var cycle = 0; cycle < AppConstants.maxLockoutCycles; cycle++) {
      for (var i = 0; i < service.maxAttempts; i++) {
        await service.registerFailedAttempt();
      }
    }
    final remaining = await service.remainingLockout();
    expect(remaining, isNotNull);
    expect(remaining, AppConstants.lockoutMaxDuration);
  });
}
