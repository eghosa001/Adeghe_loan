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
///  * Lockout cycles are cumulative and never cleared by a clock change, so
///    forwarding the device clock cannot restore unlimited guessing.
class PinLockoutService {
  PinLockoutService(this._storage);

  final SecureKeyValueStore _storage;

  int get maxAttempts => AppConstants.maxPinAttempts;
  Duration get lockoutDuration => AppConstants.lockoutDuration;

  /// Whether the user is currently locked out, including a permanent lock.
  Future<bool> isLockedOut() async {
    if (await isPermanentlyLocked()) return true;
    final until = await _lockoutUntil();
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    await _storage.remove(AppConstants.keyLockoutUntil);
    await _storage.remove(AppConstants.keyFailedAttempts);
    return false;
  }

  /// After [AppConstants.maxLockoutCycles] lockouts the device is permanently
  /// locked. Only the recovery password can unlock it again.
  Future<bool> isPermanentlyLocked() async {
    final value = await _storage.read(AppConstants.keyPermanentLock);
    return value == '1';
  }

  /// Remaining lockout duration, or null when not locked out. Returns a long
  /// fixed duration for a permanent lock so callers show a stable "locked"
  /// state instead of a nonsense countdown.
  Future<Duration?> remainingLockout() async {
    if (await isPermanentlyLocked()) {
      return AppConstants.lockoutMaxDuration;
    }
    final until = await _lockoutUntil();
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative) {
      await _storage.remove(AppConstants.keyLockoutUntil);
      await _storage.remove(AppConstants.keyFailedAttempts);
      return null;
    }
    return remaining;
  }

  /// Records a failed attempt. Returns true when this attempt starts (or
  /// continues) a lockout.
  Future<bool> registerFailedAttempt() async {
    if (await isPermanentlyLocked()) return true;
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
      await _storage.remove(AppConstants.keyLockoutUntil);
    } else {
      final until = DateTime.now().add(_escalatedDuration(cycles));
      await _storage.write(
          AppConstants.keyLockoutUntil, until.toIso8601String());
    }
    return true;
  }

  /// Clears the counter, any active lockout, and lockout cycles (after a
  /// successful unlock or recovery).
  Future<void> reset() async {
    await _storage.remove(AppConstants.keyLockoutUntil);
    await _storage.remove(AppConstants.keyFailedAttempts);
    await _storage.remove(AppConstants.keyLockoutCycles);
    await _storage.remove(AppConstants.keyPermanentLock);
  }

  /// Doubles the base lockout each cycle, capped at [AppConstants.lockoutMaxDuration].
  Duration _escalatedDuration(int cycles) {
    final multiplier = 1 << min(cycles - 1, 16);
    final duration = lockoutDuration * multiplier;
    return duration > AppConstants.lockoutMaxDuration
        ? AppConstants.lockoutMaxDuration
        : duration;
  }

  Future<int> _failedAttempts() async {
    final value = await _storage.read(AppConstants.keyFailedAttempts);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<int> _lockoutCycles() async {
    final value = await _storage.read(AppConstants.keyLockoutCycles);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<DateTime?> _lockoutUntil() async {
    final value = await _storage.read(AppConstants.keyLockoutUntil);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}
