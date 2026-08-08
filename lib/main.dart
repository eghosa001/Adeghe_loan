import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/cloud/supabase_config.dart';
import 'core/cloud/secure_cloud_storage.dart';
import 'core/di/providers.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/widgets/inactivity_wrapper.dart';
import 'features/business/presentation/providers/business_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Global error handlers: unhandled framework errors still render the debug
  // red screen during development, and release builds log them instead of
  // terminating (a transient async error must not kill a live session that
  // holds financial data). Errors also hit the default handler so tooling
  // (test runner / flutter logs) still sees them.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled async error: $error\n$stack');
    return kDebugMode ? false : true;
  };
  if (SupabaseConfig.isConfigured) {
    try {
      // The cloud auth session is persisted in flutter_secure_storage (not
      // plaintext SharedPreferences), and Android Auto Backup is disabled in
      // the manifest so tokens never leave the device in the clear.
      const secureCloudStorage = FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'AdegheSecureStorage',
          publicKey: 'AdegheSecureStoragePublicKey',
        ),
      );
      await Supabase.initialize(
        url: SupabaseConfig.supabaseUrl,
        publishableKey: SupabaseConfig.anonKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureCloudLocalStorage(secureCloudStorage),
          pkceAsyncStorage: SecureCloudAsyncStorage(secureCloudStorage),
        ),
      );
    } catch (_) {
      // Offline-first: the app runs normally even if the cloud is unreachable
      // or misconfigured. Sync simply does not happen.
    }
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  /// Periodic background sync: while the app is unlocked, a full push+pull
  /// runs on this cadence so changes made on one device (loans, repayment
  /// schedules, payments, customers, savings) appear on the other device
  /// within a couple of minutes without requiring a lock/unlock cycle.
  /// The sync service additionally throttles to one attempt per
  /// `_minAutoSyncInterval` and no-ops when not signed in / not configured.
  static const Duration _periodicSyncInterval = Duration(minutes: 2);

  Timer? _periodicSyncTimer;

  /// The instant the app was last backgrounded (`AppLifecycleState.paused`).
  /// Used to apply the session-timeout grace period on return: backgrounding no
  /// longer locks immediately — the app only re-locks when the user returns
  /// after the timeout (default 5 minutes) has elapsed. Returning within the
  /// grace period resumes the unlocked session without a PIN prompt.
  DateTime? _pausedAt;

  /// Fires if the app stays backgrounded past the timeout. Dart timers are
  /// suspended while the app is paused, so this is best-effort; the elapsed
  /// check in [didChangeAppLifecycleState] (on `resumed`) is the authoritative
  /// lock decision and makes this timer redundant on platforms that freeze it.
  Timer? _backgroundLockTimer;

  Duration get _sessionTimeout => Duration(
        minutes: ref.read(sessionTimeoutMinutesProvider).valueOrNull ??
            AppConstants.defaultInactivityTimeout.inMinutes,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    _backgroundLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      final timeout = _sessionTimeout;
      _backgroundLockTimer?.cancel();
      _backgroundLockTimer = Timer(timeout, () {
        ref.read(authProvider.notifier).lock();
      });
    } else if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel();
      _backgroundLockTimer = null;
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null &&
          DateTime.now().difference(pausedAt) >= _sessionTimeout) {
        ref.read(authProvider.notifier).lock();
      }
    }
  }

  void _syncInBackground() {
    ref.read(cloudSyncServiceProvider.future).then((service) {
      service.syncIfSignedIn();
    }).catchError((_) {});
  }

  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer =
        Timer.periodic(_periodicSyncInterval, (_) => _syncInBackground());
  }

  void _stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod requires ref.listen to be called inside build (not initState).
    // Run an auto-backup once after the app is unlocked (if enabled in
    // settings and none was created in the last 24h).
    ref.listen(authProvider, (previous, next) {
      if (next == AuthState.unlocked && previous != AuthState.unlocked) {
        // Auto-backup is deliberately deferred: running it at unlock adds a
        // multi-MB disk write that contends with the database providers still
        // initializing. Give the app time to settle, and skip if the user has
        // already locked again by the time the timer fires.
        Future.delayed(AppConstants.autoBackupDelay, () {
          if (ref.read(authProvider) != AuthState.unlocked) return;
          ref.read(backupServiceProvider.future).then((service) {
            service.maybeAutoBackup();
          }).catchError((_) {});
        });
        // Cloud sync runs in the background whenever the owner is signed in.
        _syncInBackground();
        _startPeriodicSync();
      } else if (next != AuthState.unlocked) {
        _stopPeriodicSync();
      }
    });

    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);
    final timeoutMinutes = ref
            .watch(sessionTimeoutMinutesProvider)
            .valueOrNull ??
        AppConstants.defaultInactivityTimeout.inMinutes;

    return InactivityWrapper(
      timeout: Duration(minutes: timeoutMinutes),
      onInactivity: () {
        ref.read(authProvider.notifier).lock();
      },
      child: MaterialApp.router(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: router,
      ),
    );
  }
}
