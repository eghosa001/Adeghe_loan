/// Cloud-sync configuration for Supabase.
///
/// For security, do NOT hardcode secrets in source. Build the app with the
/// Supabase values supplied at build time using Dart defines:
///
///   flutter run --dart-define=SUPABASE_URL=https://<project>.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=<anon-key>
///
/// Or pass the same defines to `flutter build` / CI. When the defines are not
/// provided the app remains offline-only and cloud sync is disabled.
class SupabaseConfig {
  SupabaseConfig._();

  /// Supply your Supabase project URL at build time with `--dart-define`.
  /// Example: `--dart-define=SUPABASE_URL=https://abcdxyz.supabase.co`
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  /// Supply your Supabase public (anon) key at build time with `--dart-define`.
  /// Example: `--dart-define=SUPABASE_ANON_KEY=eyJhbGci...`
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Storage bucket that holds the encrypted customer documents. Must be
  /// created with the `supabase_schema.sql` script.
  static const String documentsBucket = 'documents';

  /// Whether the runtime configuration is present (both URL and anon key).
  /// Avoid treating the anon key as secret in the client — the service role
  /// key must never be shipped to clients. If either value is missing the app
  /// will keep operating offline-only.
  static bool get isConfigured {
    return supabaseUrl.isNotEmpty && anonKey.isNotEmpty &&
        !supabaseUrl.contains('YOUR-PROJECT-URL') &&
        !anonKey.contains('YOUR-ANON-KEY');
  }

  /// The Unix-epoch second at which the [anonKey] JWT expires (the `exp`
  /// claim). Keep this value in sync with the anon key's `exp` claim when
  /// providing it; a wrong value only affects the expiry warning surface.
  static const int anonKeyExpiresAtEpochSeconds = 2101185634;

  /// Seconds between now and [anonKeyExpiresAtEpochSeconds]. Negative when the
  /// key has already expired.
  static int anonKeySecondsToExpiry() =>
      anonKeyExpiresAtEpochSeconds -
      DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// The warning threshold: warn the operator when the anon key has under this
  /// many days left before expiry, so they can rotate it before requests start
  /// failing (30 days of runway).
  static const int anonKeyExpiryWarningDays = 30;

  /// Whether the anon key is expired or close to expiry and the operator
  /// should be warned to rotate it before cloud sync fails.
  static bool get anonKeyExpiryImminent {
    if (!isConfigured) return false;
    return anonKeySecondsToExpiry() < anonKeyExpiryWarningDays * 24 * 3600;
  }
}
