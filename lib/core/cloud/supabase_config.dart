/// Cloud-sync configuration for Supabase.
///
/// Fill in [supabaseUrl] and [anonKey] from your Supabase project dashboard
/// (Project Settings → API). Until real values are provided the app keeps
/// running fully offline and simply never syncs.
class SupabaseConfig {
  SupabaseConfig._();

  /// Your Supabase project URL, e.g. `https://abcdxyz.supabase.co`.
  static const String supabaseUrl = 'https://tpqyilakpsjmevqgdqur.supabase.co';

  /// Your Supabase project `anon` public key.
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRwcXlpbGFrcHNqbWV2cWdkcXVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU2MDk2MzQsImV4cCI6MjEwMTE4NTYzNH0.-OcBMI2cLOyNQTu7w74cPOyzWZiekltDcexxiIsleak';

  /// Storage bucket that holds the encrypted customer documents. Must be
  /// created with the `supabase_schema.sql` script.
  static const String documentsBucket = 'documents';

  /// Whether the placeholder values are still present (i.e. sync is disabled).
  static bool get isConfigured {
    return !supabaseUrl.contains('YOUR-PROJECT-URL') &&
        !anonKey.contains('YOUR-ANON-KEY');
  }

  /// The Unix-epoch second at which the [anonKey] JWT expires (the `exp`
  /// claim). When it reaches zero seconds the anon key no longer authorizes
  /// Supabase requests and the app would silently stop syncing.
  ///
  /// IMPORTANT: keep this in sync with the `exp` claim in [anonKey]. A wrong
  /// value only affects the surface of the expiring-key warning, never the
  /// actual auth (`expsInSeconds`) — that is signed into the JWT itself.
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
