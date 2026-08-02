import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Thin wrapper around Supabase Auth used for the optional cloud-sync account
/// link. The local PIN/biometric app lock is unaffected by this — Supabase
/// sign-in only gates cloud replication, never local data access.
///
/// The client is resolved lazily so this service can be constructed even when
/// Supabase was never initialized (placeholder config); every accessor guards
/// against that and safely reports "not signed in".
class CloudAuthService {
  CloudAuthService({this.client});

  final SupabaseClient? client;

  SupabaseClient get instanceClient => client ?? Supabase.instance.client;

  bool get isConfigured => SupabaseConfig.isConfigured;

  bool get isSignedIn {
    if (!isConfigured) return false;
    try {
      return instanceClient.auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  String? get userEmail {
    if (!isConfigured) return null;
    try {
      return instanceClient.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  Stream<AuthState> get onAuthStateChange =>
      instanceClient.auth.onAuthStateChange;

  /// One-time sign-in linking the device to the cloud account. The owner
  /// account is created once in the Supabase dashboard (Auth → Users → Add user).
  Future<void> signIn(String email, String password) async {
    await instanceClient.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await instanceClient.auth.signOut();
  }
}