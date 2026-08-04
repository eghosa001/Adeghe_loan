import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/cloud/cloud_auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/di/providers.dart';

/// Pre-entry cloud sign-in gate shown right after PIN unlock. The owner signs
/// in here so cloud sync can start immediately. A "Continue offline" escape
/// hatch keeps the app usable when the cloud is unreachable.
class CloudGateScreen extends ConsumerStatefulWidget {
  const CloudGateScreen({super.key});

  @override
  ConsumerState<CloudGateScreen> createState() => _CloudGateScreenState();
}

class _CloudGateScreenState extends ConsumerState<CloudGateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _message;

  static final RegExp _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      await ref.read(cloudAuthServiceProvider).signIn(email, password);
      if (!mounted) return;
      _enterApp();
      _syncInBackground();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = CloudAuthService.friendlySignInError(error);
        });
      }
    }
  }

  void _syncInBackground() {
    ref.read(cloudSyncServiceProvider.future).then((service) {
      return service.fullSync();
    }).then((_) {}).catchError((_) {});
  }

  void _enterApp() {
    setState(() => _busy = false);
    GoRouter.of(context).go('/dashboard');
  }

  void _continueOffline() {
    ref.read(cloudGateDismissedProvider.notifier).state = true;
    GoRouter.of(context).go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColor, Color(0xFF0D2B3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.cloud_sync,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Cloud sync',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to start syncing your data to the cloud. '
                          'Your app stays locked with your PIN.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
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
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _busy ? null : _signIn,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: const Text('Sign in and sync'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _continueOffline,
                          child: const Text('Continue offline'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
