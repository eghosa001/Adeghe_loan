import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loantrack/core/cloud/cloud_auth_service.dart';
import 'package:loantrack/core/cloud/supabase_config.dart';
import 'package:loantrack/core/di/providers.dart';
import 'package:loantrack/core/widgets/app_drawer.dart';
import 'package:loantrack/core/widgets/keyboard_scrollable.dart';

/// Cloud sync: link the app to Supabase and run a manual sync. The local PIN
/// lock stays the only way to open the app — the cloud account is optional and
/// only gates data replication.
class CloudSyncScreen extends ConsumerStatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  ConsumerState<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends ConsumerState<CloudSyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;
  DateTime? _lastSync;

  static final RegExp _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  @override
  void initState() {
    super.initState();
    _loadLastSync();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSync() async {
    final service = await ref.read(cloudSyncServiceProvider.future);
    final last = await service.lastSyncTime();
    if (mounted) setState(() => _lastSync = last);
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = ref.read(cloudAuthServiceProvider);
      await auth.signIn(email, password);
      if (mounted) {
        setState(() => _message = 'Signed in. Syncing…');
      }
      await _syncNow();
    } catch (error) {
      if (mounted) {
        setState(() => _message = CloudAuthService.friendlySignInError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(cloudAuthServiceProvider).signOut();
      ref.read(cloudGateDismissedProvider.notifier).state = false;
      _passwordController.clear();
      if (mounted) {
        setState(() {
          _message = 'Signed out. Local data is unchanged.';
          _lastSync = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _message = 'Syncing…';
    });
    try {
      final service = await ref.read(cloudSyncServiceProvider.future);
      final result = await service.fullSync();
      if (!mounted) return;
      setState(() {
        _message = result.success
            ? 'Sync complete — ${result.pushedRows} pushed, '
                '${result.pulledRows} pulled, ${result.deletedRows} deleted.'
            : 'Sync finished with errors: ${result.error}';
        _lastSync = DateTime.now();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _message =
            'Sync failed. Check your internet connection and try again.\n$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(cloudAuthServiceProvider);
    final signedIn = auth.isSignedIn;
    final email = auth.userEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Sync')),
      drawer: const AppDrawer(currentRoute: '/settings'),
      body: KeyboardScrollable(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        signedIn ? Icons.cloud_done : Icons.cloud_off,
                        color: signedIn
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          signedIn ? 'Signed in' : 'Not connected',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your data stays encrypted on this device and is '
                    'replicated to your cloud in the background. Transfers are '
                    'encrypted in transit and the cloud copy is locked to the '
                    'two owners, but only customer documents are '
                    'end-to-end encrypted at rest. Regulated identifiers '
                    '(BVN/NIN) never leave this device. You always need the '
                    'local PIN to open the app.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Auto-sync runs right after the app is unlocked and every '
                    '2 minutes while it is open, so loans, repayment '
                    'schedules, payments and savings appear on the other '
                    'device within a couple of minutes of a change.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),

          if (SupabaseConfig.anonKeyExpiryImminent)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Warning: the cloud anon key expires in under '
                  '${SupabaseConfig.anonKeyExpiryWarningDays} days'
                  '${SupabaseConfig.anonKeySecondsToExpiry() < 0 ? ' (already expired)' : ''}. '
                  'Cloud sync will stop working once it expires. Rotate the key '
                  'in your Supabase dashboard and update '
                  'lib/core/cloud/supabase_config.dart.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ),

          if (!SupabaseConfig.isConfigured)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Cloud sync is not configured yet. Add your Supabase '
                  'project URL and anon key in '
                  'lib/core/cloud/supabase_config.dart, then rebuild.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer),
                ),
              ),
            ),

          const SizedBox(height: 16),

          if (!signedIn) ...[
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailController,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Enter your email.';
                      if (!_emailPattern.hasMatch(email)) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _signIn(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Enter your password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_circle),
              title: const Text('Cloud account'),
              subtitle: Text(email ?? ''),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _lastSync == null
                  ? 'Never synced yet'
                  : 'Last synced: ${_lastSync!.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],

          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
        ),
      ),
    );
  }
}
