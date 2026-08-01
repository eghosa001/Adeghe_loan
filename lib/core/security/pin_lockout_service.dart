import '../constants/app_constants.dart';
import 'secure_key_value_store.dart';

/// Shared, persisted PIN attempt limiting used by the login, forgot-PIN, and
/// change-PIN flows. State survives app restarts (backed by secure storage),
/// so lockout cannot be bypassed by relaunching the app.
class PinLockoutService {
  PinLockoutService(this._storage);

  final SecureKeyValueStore _storage;

  int get maxAttempts => AppConstants.maxPinAttempts;
  Duration get lockoutDuration => AppConstants.lockoutDuration;

  /// Whether the user is currently locked out. Expires the lockout lazily once
  /// its end time passes.
  Future<bool> isLockedOut() async {
    final until = await _lockoutUntil();
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    await _storage.remove(AppConstants.keyLockoutUntil);
    await _storage.remove(AppConstants.keyFailedAttempts);
    return false;
  }

  /// Remaining lockout duration, or null when not locked out.
  Future<Duration?> remainingLockout() async {
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

  /// Records a failed attempt. Returns true when this attempt starts a lockout.
  Future<bool> registerFailedAttempt() async {
    final attempts = await _failedAttempts();
    final next = attempts + 1;
    await _storage.write(AppConstants.keyFailedAttempts, '$next');
    if (next >= maxAttempts) {
      final until = DateTime.now().add(lockoutDuration);
      await _storage.write(AppConstants.keyLockoutUntil, until.toIso8601String());
      return true;
    }
    return false;
  }

  /// Clears the counter and any active lockout (after a successful unlock).
  Future<void> reset() async {
    await _storage.remove(AppConstants.keyLockoutUntil);
    await _storage.remove(AppConstants.keyFailedAttempts);
  }

  Future<int> _failedAttempts() async {
    final value = await _storage.read(AppConstants.keyFailedAttempts);
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<DateTime?> _lockoutUntil() async {
    final value = await _storage.read(AppConstants.keyLockoutUntil);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}
