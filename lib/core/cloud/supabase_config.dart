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
}
