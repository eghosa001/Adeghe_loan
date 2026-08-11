import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/features/reports/presentation/providers/report_provider.dart';

void main() {
  test('invalidateReportData invalidates every report family', () {
    final invalidated = <ProviderOrFamily>[];
    invalidateReportData(invalidated.add);

    expect(invalidated, contains(reportSummaryProvider));
    expect(invalidated, contains(reportDashboardProvider));
    expect(invalidated, contains(dashboardTrendsProvider));
    expect(invalidated, contains(profitReportProvider));
    expect(invalidated, contains(overdueReportProvider));
    expect(invalidated, contains(customerReportProvider));
    expect(invalidated, contains(savingsReportProvider));
    expect(invalidated, hasLength(7));
  });
}
