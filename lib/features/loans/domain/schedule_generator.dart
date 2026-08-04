import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:uuid/uuid.dart';

/// A pure-logic service that generates a list of due dates for a loan,
/// automatically skipping weekends and user-defined holidays.
class ScheduleGenerator {
  ScheduleGenerator._();

  /// Generates a full repayment schedule for a given loan's parameters.
  /// - Daily loans count forward [duration] working days.
  /// - Weekly loans advance week-by-week, shifting non-working days forward.
  ///
  /// [amounts] holds the per-installment amount for each of the [duration]
  /// installments (usually produced by `CurrencyUtils.splitEvenly` so their
  /// sum exactly equals `total_repayment`).
  static List<RepaymentInstallment> generate({
    required String loanId,
    required LoanType loanType,
    required DateTime startDate,
    required List<double> amounts,
    required List<Holiday> holidays,
  }) {
    if (loanType == LoanType.weekly) {
      return _generateWeekly(
        loanId: loanId,
        startDate: startDate,
        amounts: amounts,
        holidays: holidays,
      );
    }
    return _generateDaily(
      loanId: loanId,
      startDate: startDate,
      amounts: amounts,
      holidays: holidays,
    );
  }

  /// Generates [count] due dates continuing after [afterDate] (the last kept
  /// installment's due date) for a loan that already has paid installments:
  /// daily loans advance to the next working day, weekly loans advance a full
  /// week then shift forward past any non-working day. Used by holiday-driven
  /// schedule regeneration so only the pending tail of a partially-paid loan
  /// is re-dated while paid installments stay untouched.
  static List<DateTime> generateContinuationDueDates({
    required LoanType loanType,
    required DateTime afterDate,
    required int count,
    required List<Holiday> holidays,
  }) {
    final dates = <DateTime>[];
    var current = AppDateUtils.stripTime(afterDate);
    for (var i = 0; i < count; i++) {
      current = loanType == LoanType.weekly
          ? current.add(const Duration(days: 7))
          : current.add(const Duration(days: 1));
      current = _findNextWorkingDay(current, holidays);
      dates.add(current);
    }
    return dates;
  }

  static List<RepaymentInstallment> _generateDaily({
    required String loanId,
    required DateTime startDate,
    required List<double> amounts,
    required List<Holiday> holidays,
  }) {
    final schedule = <RepaymentInstallment>[];
    var currentDate = AppDateUtils.stripTime(startDate);
    var installmentsAdded = 0;

    while (installmentsAdded < amounts.length) {
      // Find the next working day, including today if it's a working day
      currentDate = _findNextWorkingDay(currentDate, holidays);
      schedule.add(
        RepaymentInstallment(
          id: const Uuid().v4(),
          loanId: loanId,
          installmentNumber: installmentsAdded + 1,
          dueDate: currentDate,
          amount: amounts[installmentsAdded],
        ),
      );
      installmentsAdded++;
      // Move to the next calendar day to start the search for the next installment
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return schedule;
  }

  static List<RepaymentInstallment> _generateWeekly({
    required String loanId,
    required DateTime startDate,
    required List<double> amounts,
    required List<Holiday> holidays,
  }) {
    final schedule = <RepaymentInstallment>[];
    var currentDate = AppDateUtils.stripTime(startDate);
    for (var i = 1; i <= amounts.length; i++) {
      final dueDate = _findNextWorkingDay(currentDate, holidays);
      schedule.add(
        RepaymentInstallment(
          id: const Uuid().v4(),
          loanId: loanId,
          installmentNumber: i,
          dueDate: dueDate,
          amount: amounts[i - 1],
        ),
      );
      // Move to the next week for the following installment
      currentDate = currentDate.add(const Duration(days: 7));
    }
    return schedule;
  }

  static DateTime _findNextWorkingDay(DateTime date, List<Holiday> holidays) {
    var nextDay = AppDateUtils.stripTime(date);
    while (!_isWorkingDay(nextDay, holidays)) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
  }

  static bool _isWorkingDay(DateTime date, List<Holiday> holidays) {
    if (AppDateUtils.isWeekend(date)) {
      return false;
    }

    for (final holiday in holidays) {
      if (holiday.isEnabled) {
        if (holiday.isRecurring) {
          if (holiday.date.month == date.month && holiday.date.day == date.day) {
            return false;
          }
        } else {
          if (AppDateUtils.isSameDay(holiday.date, date)) {
            return false;
          }
        }
      }
    }
    return true;
  }
}
