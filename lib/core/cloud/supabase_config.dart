/// Cloud-sync configuration for Supabase.
///
/// Supply the URL and public anon key at build time with Dart defines. The
/// service-role key must never be compiled into the client.
class SupabaseConfig {
  SupabaseConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String documentsBucket = 'documents';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && anonKey.isNotEmpty;

  /// Zero means the key expiry is supplied externally and is not committed.
  static const int anonKeyExpiresAtEpochSeconds = 0;

  static int anonKeySecondsToExpiry() {
    if (anonKeyExpiresAtEpochSeconds == 0) return 0;
    return anonKeyExpiresAtEpochSeconds -
        DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static const int anonKeyExpiryWarningDays = 30;

  static bool get anonKeyExpiryImminent {
    if (!isConfigured || anonKeyExpiresAtEpochSeconds == 0) return false;
    return anonKeySecondsToExpiry() < anonKeyExpiryWarningDays * 24 * 3600;
  }
}
