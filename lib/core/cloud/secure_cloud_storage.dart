import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [LocalStorage] that persists the Supabase auth session in
/// `flutter_secure_storage` instead of plaintext `SharedPreferences`.
///
/// Without this, supabase_flutter stores the access token and refresh token in
/// an unencrypted shared-prefs XML file that Android Auto Backup can also copy
/// to Google Drive.
class SecureCloudLocalStorage extends LocalStorage {
  SecureCloudLocalStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'supabase_auth_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: _sessionKey)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _sessionKey, value: persistSessionString);
}

/// [GotrueAsyncStorage] for the PKCE code verifier, also secure-storage backed.
class SecureCloudAsyncStorage extends GotrueAsyncStorage {
  SecureCloudAsyncStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const String _keyPrefix = 'supabase_pkce_';

  String _key(String key) => '$_keyPrefix$key';

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: _key(key));

  @override
  Future<void> setItem({required String key, required String value}) =>
      _storage.write(key: _key(key), value: value);

  @override
  Future<void> removeItem({required String key}) =>
      _storage.delete(key: _key(key));
}
