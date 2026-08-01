/// Minimal key/value persistence abstraction over secure storage, so that
/// services using it (e.g. [PinLockoutService]) can be unit-tested with an
/// in-memory fake instead of the platform plugin.
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}
