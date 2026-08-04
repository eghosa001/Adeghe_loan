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
  CloudAuthService({
    this.client,
    Future<dynamic> Function(String fn, {Map<String, dynamic>? params})? rpc,
  }) : _rpcOverride = rpc;

  final SupabaseClient? client;
  final Future<dynamic> Function(String fn, {Map<String, dynamic>? params})?
      _rpcOverride;

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

  /// RPC seam (overridable in tests). Delegates to the Supabase REST `rpc`.
  Future<dynamic> _callRpc(String fn, {Map<String, dynamic>? params}) {
    final override = _rpcOverride;
    if (override != null) return override(fn, params: params);
    return instanceClient.rpc(fn, params: params);
  }

  /// Sign-in linking the device to the cloud. Owner accounts are created in the
  /// Supabase dashboard (Auth → Users → Add user); the first TWO distinct
  /// accounts to sign in become the project owners.
  ///
  /// After a successful password sign-in the device calls the `claim_owner`
  /// RPC (see supabase_schema.sql). That SECURITY DEFINER function derives the
  /// owner id from `auth.uid()` server-side — the caller cannot nominate an
  /// arbitrary account — and only inserts while fewer than two owners exist.
  /// The sign-in then verifies the caller really IS an owner via `is_owner`;
  /// a non-owner session is signed back out so it can never sync data.
  Future<void> signIn(String email, String password) async {
    await instanceClient.auth
        .signInWithPassword(email: email, password: password);
    final user = instanceClient.auth.currentUser;
    if (user == null) return;
    try {
      await _callRpc('claim_owner');
      final isOwner = await _callRpc('is_owner') == true;
      if (!isOwner) {
        await instanceClient.auth.signOut();
        throw StateError(notOwnerMessage);
      }
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError(
          'Cloud is misconfigured: run the updated supabase_schema.sql '
          '(two-owner policy) on your Supabase project, then sign in again.');
    }
  }

  /// Message shown when a valid cloud account is not one of the two owners.
  static const String notOwnerMessage =
      'This account is not one of the cloud owners. '
      'Sign in with an owner account.';

  Future<void> signOut() async {
    await instanceClient.auth.signOut();
  }

  /// Maps Supabase sign-in failures to safe, non-enumerating user messages.
  /// Raw GoTrue errors are never shown because "Email not registered" vs
  /// "Invalid login credentials" would leak which accounts exist.
  static String friendlySignInError(Object error) {
    final message = error is AuthException ? error.message : '$error';
    final lower = message.toLowerCase();
    if (lower.contains('not one of the cloud owners') ||
        lower.contains('not authorized') ||
        lower.contains('owner')) {
      return notOwnerMessage;
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('not registered') ||
        lower.contains('email not found') ||
        lower.contains('invalid email')) {
      return 'Invalid email or password.';
    }
    if (lower.contains('confirmed') || lower.contains('verified')) {
      return 'This email has not been confirmed. Check your inbox.';
    }
    if (lower.contains('misconfigured') ||
        lower.contains('supabase_schema.sql')) {
      return 'Cloud setup is outdated. Run the updated supabase_schema.sql on '
          'your Supabase project, then try again.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('timeout') ||
        lower.contains('connection') ||
        lower.contains('internet')) {
      return 'Could not reach the cloud. Check your internet connection.';
    }
    return 'Sign-in failed. Please try again.';
  }
}