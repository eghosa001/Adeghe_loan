import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../di/providers.dart';
import '../cloud/supabase_config.dart';
import '../widgets/scaffold_with_nav_bar.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/pin_setup_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
import '../../features/auth/presentation/screens/forgot_pin_screen.dart';
import '../../features/auth/presentation/screens/change_pin_screen.dart';
import '../../features/auth/presentation/screens/security_settings_screen.dart';
import '../../features/business/presentation/screens/business_details_tab.dart';
import '../../features/business/presentation/screens/financial_settings_tab.dart';
import '../../features/backup/presentation/screens/backup_screen.dart';
import '../../features/customers/data/models/customer_entity.dart';
import '../../features/customers/presentation/screens/customer_details_screen.dart';
import '../../features/customers/presentation/screens/customer_form_screen.dart';
import '../../features/customers/presentation/screens/customer_search_screen.dart';
import '../../features/documents/data/models/document_entity.dart';
import '../../features/documents/presentation/screens/document_list_screen.dart';
import '../../features/documents/presentation/screens/document_upload_screen.dart';
import '../../features/documents/presentation/screens/secure_preview_screen.dart';
import '../../features/loans/data/models/loan_entity.dart';
import '../../features/loans/presentation/providers/loan_providers.dart';
import '../../features/loans/presentation/screens/loan_creation_screen.dart';
import '../../features/loans/presentation/screens/loan_details_screen.dart';
import '../../features/loans/presentation/screens/loan_list_screen.dart';
import '../../features/loans/presentation/screens/repayment_calendar_view.dart';
import '../../features/payments/presentation/screens/record_payment_screen.dart';
import '../../features/payments/presentation/screens/payment_history_screen.dart';
import '../../features/holidays/presentation/screens/holiday_management_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/collection/presentation/screens/daily_collection_screen.dart';
import '../../features/collection/presentation/screens/weekly_collection_screen.dart';
import '../../features/collection/presentation/screens/future_schedule_screen.dart';
import '../../features/reports/presentation/screens/report_screen.dart';
import '../../features/reports/presentation/screens/overdue_report_screen.dart';
import '../../features/reports/presentation/screens/daily_loan_report_screen.dart';
import '../../features/reports/presentation/screens/weekly_loan_report_screen.dart';
import '../../features/reports/presentation/screens/customer_report_screen.dart';
import '../../features/reports/presentation/screens/savings_report_screen.dart';
import '../../features/reports/presentation/screens/profit_report_screen.dart';
import '../../features/audit_log/presentation/screens/audit_log_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/cloud_gate_screen.dart';
import '../../features/settings/presentation/screens/cloud_sync_screen.dart';
import '../../features/groups/presentation/screens/group_management_screen.dart';
import '../../features/groups/presentation/screens/group_detail_screen.dart';
import '../../features/savings/presentation/screens/savings_overview_screen.dart';
import '../../features/customers/presentation/screens/loan_statement_screen.dart';
import '../../features/customers/presentation/screens/savings_statement_screen.dart';
import '../../features/customers/presentation/screens/collection_statement_screen.dart';
import '../../features/search/presentation/screens/global_search_screen.dart';
import '../../features/notifications/presentation/screens/notification_screen.dart';

/// Pure redirect decision for the auth guard. Returns a redirect target when
/// the current location is not allowed for the given auth state.
String? authRedirect(AuthState auth, String location) {
  if (auth == AuthState.unlocked) return null;
  final isPublic =
      location == '/splash' ||
      location == '/onboarding' ||
      location == '/auth/pin' ||
      location == '/auth/setup_pin' ||
      location == '/auth/forgot_pin';
  if (isPublic) return null;
  return auth == AuthState.initialSetup ? '/auth/setup_pin' : '/auth/pin';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthRefreshListenable(ref),
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final base = authRedirect(auth, state.uri.toString());
      if (base != null) return base;
      // Pre-entry cloud gate: after PIN unlock, ask for cloud credentials
      // before the app opens so sync can start immediately.
      if (auth == AuthState.unlocked &&
          SupabaseConfig.isConfigured &&
          !ref.read(cloudAuthServiceProvider).isSignedIn &&
          !ref.read(cloudGateDismissedProvider)) {
        final location = state.uri.toString();
        if (location != '/cloud-gate') return '/cloud-gate';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/auth/pin',
        builder: (context, state) => const PinLoginScreen(),
      ),
      GoRoute(
        path: '/auth/setup_pin',
        builder: (context, state) => const PinSetupScreen(),
      ),
      GoRoute(
        path: '/auth/forgot_pin',
        builder: (context, state) => const ForgotPinScreen(),
      ),
      GoRoute(
        path: '/auth/change_pin',
        builder: (context, state) => const ChangePinScreen(),
      ),

      // Main shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) {
          return ScaffoldWithNavBar(
            currentPath: state.uri.toString(),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/collections',
            builder: (context, state) => const DailyCollectionScreen(),
            routes: [
              GoRoute(
                path: 'weekly',
                builder: (context, state) => const WeeklyCollectionScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportScreen(),
            routes: [
              GoRoute(
                path: 'daily-loans',
                builder: (context, state) => const DailyLoanReportScreen(),
              ),
              GoRoute(
                path: 'weekly-loans',
                builder: (context, state) => const WeeklyLoanReportScreen(),
              ),
              GoRoute(
                path: 'overdue',
                builder: (context, state) => const OverdueReportScreen(),
              ),
              GoRoute(
                path: 'customers',
                builder: (context, state) => const CustomerReportScreen(),
              ),
              GoRoute(
                path: 'savings-report',
                builder: (context, state) => const SavingsReportScreen(),
              ),
              GoRoute(
                path: 'profit',
                builder: (context, state) => const ProfitReportScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/savings',
            builder: (context, state) => const SavingsOverviewScreen(),
          ),
        ],
      ),

      // Standalone routes (pushed on top of the shell)
      GoRoute(
        path: '/groups',
        builder: (context, state) => const GroupManagementScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                GroupDetailScreen(groupId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const CustomerFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) =>
                CustomerDetailScreen(customerId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) =>
                    CustomerFormScreen(customer: state.extra as Customer?),
              ),
              GoRoute(
                path: 'documents',
                builder: (context, state) =>
                    DocumentListScreen(customerId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'documents/upload',
                builder: (context, state) => DocumentUploadScreen(
                  customerId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: 'loans/new',
                builder: (context, state) =>
                    LoanCreationScreen(customerId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/loans/:id',
        builder: (context, state) =>
            LoanDetailsScreen(loanId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) {
              final loan = state.extra as Loan?;
              if (loan == null) {
                // No object passed (deep link / state restore): resolve the
                // loan from the path id instead of silently opening a blank
                // create form with an empty customer id.
                return _EditLoanLoader(
                  loanId: state.pathParameters['id']!,
                );
              }
              return LoanCreationScreen(
                customerId: loan.customerId,
                existingLoan: loan,
              );
            },
          ),
          GoRoute(
            path: 'repayment-calendar',
            builder: (context, state) =>
                RepaymentCalendarView(loanId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'payments',
            builder: (context, state) => PaymentHistoryScreen(
              loanId: state.pathParameters['id']!,
              customerId:
                  (state.extra as Map<String, dynamic>?)?['customerId']
                      as String? ??
                  '',
            ),
          ),
          GoRoute(
            path: 'record-payment',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              return RecordPaymentScreen(
                loanId: state.pathParameters['id']!,
                customerId: extra['customerId'] as String? ?? '',
                currentBalance:
                    (extra['currentBalance'] as num?)?.toDouble() ?? 0.0,
                installmentDue: (extra['installmentDue'] as num?)?.toDouble(),
                initialAmount: (extra['initialAmount'] as num?)?.toDouble(),
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/documents/preview',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! CustomerDocument) {
            // Never navigate to the preview without a document object.
            return const Scaffold(
              body: Center(child: Text('No document to preview')),
            );
          }
          return SecurePreviewScreen(document: extra);
        },
      ),
      GoRoute(
        path: '/holidays',
        builder: (context, state) => const HolidayManagementScreen(),
      ),
      GoRoute(
        path: '/audit-log',
        builder: (context, state) => const AuditLogScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/security',
        builder: (context, state) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: '/settings/business',
        builder: (context, state) => const BusinessDetailsTab(),
      ),
      GoRoute(
        path: '/settings/business/financial_defaults',
        builder: (context, state) => const FinancialSettingsTab(),
      ),
      GoRoute(
        path: '/settings/backup',
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: '/settings/cloud_sync',
        builder: (context, state) => const CloudSyncScreen(),
      ),
      GoRoute(
        path: '/cloud-gate',
        builder: (context, state) => const CloudGateScreen(),
      ),
      GoRoute(
        path: '/loans',
        builder: (context, state) => const LoanListScreen(),
      ),
      GoRoute(
        path: '/statements/loan',
        builder: (context, state) => const LoanStatementScreen(),
      ),
      GoRoute(
        path: '/statements/savings',
        builder: (context, state) => const SavingsStatementScreen(),
      ),
      GoRoute(
        path: '/statements/collection',
        builder: (context, state) => const CollectionStatementScreen(),
      ),
      GoRoute(
        path: '/collections/future-schedule',
        builder: (context, state) => const FutureScheduleScreen(),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => const GlobalSearchScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Route error: ${state.error}'))),
  );
});

/// Fires GoRouter's redirect re-evaluation whenever the auth state changes,
/// so locking/unlocking immediately moves the user to the correct screen.
class _AuthRefreshListenable extends Listenable {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(authProvider, (_, _) => _notify());
  }

  final Set<VoidCallback> _listeners = {};

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  /// Set when secure storage could not be read after several attempts. The
  /// splash then shows a Retry panel instead of spinning forever — on Windows
  /// the Credential Manager (flutter_secure_storage) can transiently fail at
  /// cold start, which previously stranded the user on this screen.
  bool _initFailed = false;

  static const int _maxInitAttempts = 3;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (mounted) setState(() => _initFailed = false);
    final startedAt = DateTime.now();
    var hasPin = false;
    var ok = false;

    for (var attempt = 0; attempt < _maxInitAttempts; attempt++) {
      try {
        final secure = ref.read(secureStorageProvider);
        await secure.migrateToFourDigitPin();
        hasPin = await secure.hasPin();
        ok = true;
        break;
      } catch (e) {
        debugPrint('Splash init attempt ${attempt + 1} failed: $e');
        if (!mounted) return;
        if (attempt < _maxInitAttempts - 1) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
        }
      }
    }

    if (!mounted) return;
    if (!ok) {
      setState(() => _initFailed = true);
      return;
    }

    // Keep a minimum splash display time so the logo is not a flash.
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < const Duration(milliseconds: 1500)) {
      await Future.delayed(const Duration(milliseconds: 1500) - elapsed);
    }
    if (!mounted) return;
    GoRouter.of(context).go(hasPin ? '/auth/pin' : '/auth/setup_pin');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A1628), Color(0xFF0D2B3E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _initFailed ? _buildInitError() : _buildSplash(),
      ),
    );
  }

  Widget _buildInitError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: Color(0xFFD4A847)),
            const SizedBox(height: 16),
            const Text(
              'Unable to open secure storage',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This usually means the Windows Credential Manager is temporarily '
              'unavailable. Retry, or close and reopen the app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplash() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4A847), Color(0xFFF5D77A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD4A847).withValues(alpha: 0.3),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0A1628),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Adeghe Professional Services',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Created by AIGHEWI EGHOSA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD4A847),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Professional Services Management',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: const Color(0xFFD4A847).withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => GoRouter.of(context).go('/auth/pin'),
          child: const Text('Continue'),
        ),
      ),
    );
  }
}

/// Resolves a loan by id for the `/loans/:id/edit` route when navigation did
/// not pass the `Loan` object (deep link / state restore). Prevents a blank
/// create form with an empty customer id from being opened.
class _EditLoanLoader extends ConsumerWidget {
  const _EditLoanLoader({required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loanAsync = ref.watch(loanDetailsProvider(loanId));
    return loanAsync.when(
      data: (loan) => LoanCreationScreen(
        customerId: loan.customerId,
        existingLoan: loan,
      ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Edit Loan')),
        body: Center(child: Text('Failed to load loan: $e')),
      ),
    );
  }
}
