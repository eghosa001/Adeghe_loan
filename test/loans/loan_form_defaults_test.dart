import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loantrack/core/constants/app_constants.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/presentation/providers/loan_providers.dart';

void main() {
  test('new loan form starts with the daily defaults (15%, 23 days)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(loanFormProvider);
    expect(state.loanType, LoanType.daily);
    expect(state.interestRatePercent, AppConstants.defaultDailyInterestRate);
    expect(state.duration, AppConstants.defaultDailyDurationDays);
    expect(state.calculationResult, isNotNull);
  });

  test('switching to weekly applies the weekly defaults (20%, 12 weeks)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(loanFormProvider.notifier).selectLoanType(LoanType.weekly);

    final state = container.read(loanFormProvider);
    expect(state.loanType, LoanType.weekly);
    expect(state.interestRatePercent, AppConstants.defaultWeeklyInterestRate);
    expect(state.duration, AppConstants.defaultWeeklyDurationWeeks);
  });

  test('switching back to daily restores the daily defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(loanFormProvider.notifier);
    notifier.selectLoanType(LoanType.weekly);
    notifier.selectLoanType(LoanType.daily);

    final state = container.read(loanFormProvider);
    expect(state.loanType, LoanType.daily);
    expect(state.interestRatePercent, AppConstants.defaultDailyInterestRate);
    expect(state.duration, AppConstants.defaultDailyDurationDays);
  });
}
