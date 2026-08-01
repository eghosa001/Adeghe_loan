import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/di/providers.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/widgets/inactivity_wrapper.dart';
import 'features/business/presentation/providers/business_providers.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(authProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod requires ref.listen to be called inside build (not initState).
    // Run an auto-backup once after the app is unlocked (if enabled in
    // settings and none was created in the last 24h).
    ref.listen(authProvider, (previous, next) {
      if (next == AuthState.unlocked && previous != AuthState.unlocked) {
        ref.read(backupServiceProvider.future).then((service) {
          service.maybeAutoBackup();
        }).catchError((_) {});
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
