import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../di/providers.dart';
import '../../features/auth/presentation/screens/pin_setup_screen.dart';
import '../../features/auth/presentation/screens/pin_login_screen.dart';
import '../../features/auth/presentation/screens/forgot_pin_screen.dart';
import '../../features/auth/presentation/screens/change_pin_screen.dart';
import '../../features/auth/presentation/screens/security_settings_screen.dart';
import '../../features/business/presentation/screens/business_settings_screen.dart';
import '../../features/business/presentation/screens/business_details_tab.dart';
import '../../features/business/presentation/screens/financial_settings_tab.dart';
import '../../features/backup/presentation/screens/backup_screen.dart';
import '../../features/customers/data/models/customer_entity.dart';
import '../../features/customers/presentation/screens/customer_details_screen.dart';
import '../../features/customers/presentation/screens/customer_form_screen.dart';
import '../../features/customers/presentation/screens/customer_search_screen.dart';
import '../../features/documents/presentation/screens/document_list_screen.dart';
import '../../features/documents/presentation/screens/document_upload_screen.dart';
import '../../features/loans/presentation/screens/loan_creation_screen.dart';
import '../../features/loans/presentation/screens/loan_details_screen.dart';
import '../../features/loans/presentation/screens/repayment_calendar_view.dart';
import '../../features/payments/presentation/screens/record_payment_screen.dart';
import '../../features/payments/presentation/screens/payment_history_screen.dart';
import '../../features/holidays/presentation/screens/holiday_management_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/collection/presentation/screens/collection_screen.dart';
import '../../features/reports/presentation/screens/report_screen.dart';
import '../../features/audit_log/presentation/screens/audit_log_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
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
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
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
              CustomerDetailScreen(customerId: state.params['id']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  CustomerFormScreen(customer: state.extra as Customer?),
            ),
            GoRoute(
              path: 'documents',
              builder: (context, state) => DocumentListScreen(
                customerId: state.params['id']!,
              ),
            ),
            GoRoute(
              path: 'documents/upload',
              builder: (context, state) => DocumentUploadScreen(
                customerId: state.params['id']!,
              ),
            ),
            GoRoute(
              path: 'loans/new',
              builder: (context, state) => LoanCreationScreen(
                customerId: state.params['id']!,
              ),
            ),
            GoRoute(
              path: 'payments',
              builder: (context, state) => PaymentHistoryScreen(
                loanId: state.extra as String? ?? '',
                customerId: state.params['id']!,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/loans/:id',
      builder: (context, state) => LoanDetailsScreen(
        loanId: state.params['id']!,
      ),
      routes: [
        GoRoute(
          path: 'repayment-calendar',
          builder: (context, state) => RepaymentCalendarView(
            loanId: state.params['id']!,
          ),
        ),
        GoRoute(
          path: 'record-payment',
          builder: (context, state) => RecordPaymentScreen(
            loanId: state.params['id']!,
            customerId: state.extra as String? ?? '',
            currentBalance: 0,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/collections',
      builder: (context, state) => const CollectionScreen(),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) => const ReportScreen(),
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
      builder: (context, state) => const BusinessSettingsScreen(),
    ),
    GoRoute(
      path: '/settings/business/details',
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
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('Route error: ${state.error}')),
  ),
);

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final secure = ref.read(secureStorageProvider);
      final hasPin = await secure.hasPin();
      if (!mounted) return;
      if (!hasPin) {
        GoRouter.of(context).go('/auth/setup_pin');
      } else {
        GoRouter.of(context).go('/auth/pin');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'attached_assets/full_horizontal_logo_1784971585520.png',
              width: 240,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
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
