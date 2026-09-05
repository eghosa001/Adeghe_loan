import 'dart:async';
import 'dart:math';

import '../constants/app_constants.dart';
import 'secure_key_value_store.dart';

/// Shared, persisted PIN attempt limiting used by the login, forgot-PIN, and
/// change-PIN flows. State survives app restarts (backed by secure storage),
/// so lockout cannot be bypassed by relaunching the app.
///
/// Anti-brute-force design:
///  * Every `maxAttempts` failures trigger a lockout whose length DOUBLES per
///    lockout cycle (5 min, 10 min, 20 min, 40 min, then permanent).
///  * After `maxLockoutCycles` lockouts the device is PERMANENTLY locked. The
///    only way back in is the recovery password via Forgot PIN, which is a
///    long, high-entropy secret hashed with PBKDF2.
///  * Lockout state is serialized so concurrent failed-attempt callbacks cannot
///    overwrite each other's counters. Corrupt or incomplete persisted lockout
///    state fails closed by permanently locking the local authentication gate.
class PinLockoutService {
  PinLockoutService(this._storage);

  final SecureKeyValueStore _storage;
  Future<void>? _mutationTail;

  int get maxAttempts => AppConstants.maxPinAttempts;
  Duration get lockoutDuration => AppConstants.lockoutDuration;

  Future<bool> isLockedOut() async {
    if (await isPermanentlyLocked()) return true;
    if (await _hasCorruptLockoutState()) {
      await _failClosed();
      return true;
    }
    final until = await _lockoutUntil();
    if (until == null) return false;
    final now = DateTime.now();
    final started = await _lockoutStarted();
    if (started != null && now.isBefore(started)) return true;
    if (now.isBefore(until)) return true;
    await _clearActiveLockout();
    return false;
  }

  Future<bool> isPermanentlyLocked() async {
    final value = await _storage.read(AppConstants.keyPermanentLock);
    return value == '1';
  }

  Future<Duration?> remainingLockout() async {
    if (await isPermanentlyLocked()) {
      return AppConstants.lockoutMaxDuration;
    }
    if (await _hasCorruptLockoutState()) {
      await _failClosed();
      return AppConstants.lockoutMaxDuration;
    }
    final until = await _lockoutUntil();
    if (until == null) return null;
    final now = DateTime.now();
    final started = await _lockoutStarted();
    if (started != null && now.isBefore(started)) {
      return AppConstants.lockoutMaxDuration;
    }
    final remaining = until.difference(now);
    if (remaining.isNegative) {
      await _clearActiveLockout();
      return null;
    }
    return remaining;
  }

  Future<int> remainingAttempts() async {
    if (await isPermanentlyLocked()) return 0;
    final attempts = await _failedAttempts();
    return max(0, maxAttempts - attempts);
  }

  /// Serializes mutations because secure storage is not an atomic counter.
  Future<bool> registerFailedAttempt() {
    return _serializeMutation(() async {
      if (await isPermanentlyLocked()) return true;
      if (await _hasCorruptLockoutState()) {
        await _failClosed();
        return true;
      }

      final until = await _lockoutUntil();
      final started = await _lockoutStarted();
      if (until != null && started != null) {
        final now = DateTime.now();
        if (now.isBefore(started) || now.isBefore(until)) return true;
        await _clearActiveLockout();
      }

      final attempts = await _failedAttempts();
      final next = attempts + 1;
      if (next < maxAttempts) {
        await _storage.write(AppConstants.keyFailedAttempts, '$next');
        return false;
      }
      await _storage.remove(AppConstants.keyFailedAttempts);
      final cycles = await _lockoutCycles() + 1;
      await _storage.write(AppConstants.keyLockoutCycles, '$cycles');
      if (cycles >= AppConstants.maxLockoutCycles) {
        await _storage.write(AppConstants.keyPermanentLock, '1');
        await _clearActiveLockout();
      } else {
        final startedAt = DateTime.now();
        final untilAt = startedAt.add(_escalatedDuration(cycles));
        await _storage.write(
            AppConstants.keyLockoutStarted, startedAt.toIso8601String());
        await _storage.write(
            AppConstants.keyLockoutUntil, untilAt.toIso8601String());
      }
      return true;
    });
  }

  Future<void> reset() {
    return _serializeMutation(() async {
      await _clearActiveLockout();
      await _storage.remove(AppConstants.keyLockoutCycles);
      await _storage.remove(AppConstants.keyPermanentLock);
    });
  }

  Duration _escalatedDuration(int cycles) {
    final multiplier = 1 << min(cycles - 1, 16);
    final duration = lockoutDuration * multiplier;
    return duration > AppConstants.lockoutMaxDuration
        ? AppConstants.lockoutMaxDuration
        : duration;
  }

  Future<int> _failedAttempts() async {
    final value = await _storage.read(AppConstants.keyFailedAttempts);
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 0 || parsed >= maxAttempts) {
      if (value == null) return 0;
      return maxAttempts;
    }
    return parsed;
  }

  Future<int> _lockoutCycles() async {
    final value = await _storage.read(AppConstants.keyLockoutCycles);
    final parsed = int.tryParse(value ?? '');
    if (parsed == null || parsed < 0) return AppConstants.maxLockoutCycles;
    return parsed;
  }

  Future<DateTime?> _lockoutUntil() async {
    final value = await _storage.read(AppConstants.keyLockoutUntil);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<DateTime?> _lockoutStarted() async {
    final value = await _storage.read(AppConstants.keyLockoutStarted);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  Future<bool> _hasCorruptLockoutState() async {
    final untilRaw = await _storage.read(AppConstants.keyLockoutUntil);
    final startedRaw = await _storage.read(AppConstants.keyLockoutStarted);
    final attemptsRaw = await _storage.read(AppConstants.keyFailedAttempts);
    final cyclesRaw = await _storage.read(AppConstants.keyLockoutCycles);

    final hasUntil = untilRaw != null;
    final hasStarted = startedRaw != null;
    if (hasUntil != hasStarted) return true;
    if (hasUntil) {
      final until = DateTime.tryParse(untilRaw!);
      final started = DateTime.tryParse(startedRaw!);
      if (until == null || started == null || !started.isBefore(until)) {
        return true;
      }
    }
    final attempts = int.tryParse(attemptsRaw ?? '0');
    if (attempts == null || attempts < 0 || attempts >= maxAttempts) return true;
    final cycles = int.tryParse(cyclesRaw ?? '0');
    if (cycles == null || cycles < 0) return true;
    return false;
  }

  Future<void> _failClosed() async {
    await _storage.write(AppConstants.keyPermanentLock, '1');
    await _clearActiveLockout();
  }

  Future<void> _clearActiveLockout() async {
    await _storage.remove(AppConstants.keyLockoutUntil);
    await _storage.remove(AppConstants.keyLockoutStarted);
    await _storage.remove(AppConstants.keyFailedAttempts);
  }

  Future<T> _serializeMutation<T>(Future<T> Function() action) async {
    final previous = _mutationTail;
    final done = Completer<void>();
    _mutationTail = done.future;
    if (previous != null) await previous;
    try {
      return await action();
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }
}
