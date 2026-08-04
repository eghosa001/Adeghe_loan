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

  /// Sign-in linking the device to the cloud. Owner emails are allow-listed by
  /// the operator in `authorized_owners` (Supabase dashboard SQL editor) AFTER
  /// email signups are turned OFF and the owner accounts are created at Auth →
  /// Users → Add user — see supabase_schema.sql header (API-2 setup order).
  ///
  /// After a successful password sign-in the device calls the `claim_owner`
  /// RPC (see supabase_schema.sql). That SECURITY DEFINER function derives the
  /// owner id from `auth.uid()` server-side — the caller cannot nominate an
  /// arbitrary account — and only grants a slot while the caller's email is on
  /// the allow-list and fewer than two owners exist (first-come-first-served
  /// owner capture is impossible). The sign-in then verifies the caller really
  /// IS an owner via `is_owner`; a non-owner session is signed back out so it
  /// can never sync data.
  Future<void> signIn(String email, String password) async {
    await instanceClient.auth
        .signInWithPassword(email: email, password: password);
    final user = instanceClient.auth.currentUser;
    if (user == null) return;
    try {
      final claim = await _callRpc('claim_owner');
      if (claim == emailNotAuthorizedCode) {
        await instanceClient.auth.signOut();
        throw StateError(emailNotAuthorizedMessage);
      }
      if (claim == ownersFullCode) {
        await instanceClient.auth.signOut();
        throw StateError(ownersFullMessage);
      }
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

  /// `claim_owner` returns this when the caller's email is not on the
  /// operator-maintained `authorized_owners` allow-list.
  static const String emailNotAuthorizedCode = 'email_not_authorized';

  /// `claim_owner` returns this when both owner slots are already taken.
  static const String ownersFullCode = 'full';

  /// Message shown when a valid cloud account is not one of the two owners.
  static const String notOwnerMessage =
      'This account is not one of the cloud owners. '
      'Sign in with an owner account.';

  /// Message shown when the account's email is valid but not pre-authorized.
  static const String emailNotAuthorizedMessage =
      'This email is not on the authorized-owners list for this cloud. '
      'Ask the account owner to add it in the Supabase dashboard '
      '(authorized_owners table), then sign in again.';

  /// Message shown when a pre-authorized email signs in but both slots are
  /// already taken by the two existing owners.
  static const String ownersFullMessage =
      'Both cloud owner slots are already taken. '
      'Ask the owner to free a slot in the Supabase dashboard, then sign in again.';

  Future<void> signOut() async {
    await instanceClient.auth.signOut();
  }

  /// Maps Supabase sign-in failures to safe, non-enumerating user messages.
  /// Raw GoTrue errors are never shown because "Email not registered" vs
  /// "Invalid login credentials" would leak which accounts exist.
  static String friendlySignInError(Object error) {
    final message = error is AuthException ? error.message : '$error';
    final lower = message.toLowerCase();
    if (lower.contains('authorized-owners')) {
      return emailNotAuthorizedMessage;
    }
    if (lower.contains('owner slots are already taken')) {
      return ownersFullMessage;
    }
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