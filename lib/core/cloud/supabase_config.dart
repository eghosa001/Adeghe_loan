/// Cloud-sync configuration for Supabase.
///
/// The public (anon) key is safe to ship in the client — the service-role key
/// must never be compiled in. The values below are the defaults; override them
/// at build time when needed using Dart defines:
///
///   flutter run --dart-define=SUPABASE_URL=https://`<project>`.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=`<anon-key>`
///
/// The defaults are committed so cloud sync is configured out of the box.
class SupabaseConfig {
  SupabaseConfig._();

  /// The Supabase project URL (defaults committed; override via `--dart-define`).
  /// Example: `--dart-define=SUPABASE_URL=https://abcdxyz.supabase.co`
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://tpqyilakpsjmevqgdqur.supabase.co',
  );

  /// The Supabase public (anon) key (defaults committed; override via `--dart-define`).
  /// Example: `--dart-define=SUPABASE_ANON_KEY=eyJhbGci...`
  // The anon key is a publishable client key, not a secret (see doc comment).
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwcXlpbGFrcHNqbWV2cWdkcXVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2MDk2MzQsImV4cCI6MjEwMTE4NTYzNH0.-OcBMI2cLOyNQTu7w74cPOyzWZiekltDcexxiIsleak', // nosemgrep: generic.secrets.security.detected-jwt-token.detected-jwt-token
  );

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
