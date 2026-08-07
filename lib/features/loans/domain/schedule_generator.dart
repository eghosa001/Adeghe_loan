import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/loan_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';

/// A pure-logic service that generates a list of due dates for a loan,
/// automatically skipping weekends and user-defined holidays.
///
/// This is a **pure function of the loan's source data**: the same loan
/// (start date, type, duration) plus the same holiday set produces the same
/// due dates on every device. Installment ids are deterministic
/// (`<loanId>-<installmentNumber>`) so a regenerated schedule is byte-for-byte
/// identical across devices — which is what lets the app treat the stored
/// `repayment_schedule` table as a disposable derived cache instead of a
/// synchronized source of truth.
class ScheduleGenerator {
  ScheduleGenerator._();

  /// Generates a full repayment schedule for a given loan's parameters.
  /// - Daily loans count forward [duration] working days.
  /// - Weekly loans advance week-by-week. The anchor weekday is the
  ///   [startDate] weekday; an installment that lands on a non-working day
  ///   (weekend or enabled holiday) is shifted forward to the next working
  ///   day, but **only that installment** — the following installment resumes
  ///   the anchor weekday.
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
          id: '$loanId-${installmentsAdded + 1}',
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
      // Find the next working day starting from the anchor weekday
      var dueDate = _findNextWorkingDay(currentDate, holidays);
      schedule.add(
        RepaymentInstallment(
          id: '$loanId-$i',
          loanId: loanId,
          installmentNumber: i,
          dueDate: dueDate,
          amount: amounts[i - 1],
        ),
      );
      // Move to the next anchor weekday for the following installment
      // Add 7 days from the CURRENT anchor date (not the shifted due date)
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
