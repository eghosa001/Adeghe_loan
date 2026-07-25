import 'package:loantrack/core/utils/date_utils.dart';
import 'package:loantrack/features/holidays/data/models/holiday_entity.dart';
import 'package:loantrack/features/loans/data/models/repayment_installment_entity.dart';
import 'package:uuid/uuid.dart';

/// A pure-logic service that generates a list of due dates for a loan,
/// automatically skipping weekends and user-defined holidays.
class ScheduleGenerator {
  ScheduleGenerator._();

  /// Generates a full daily repayment schedule for a given loan's parameters.
  /// Counts forward [duration] working days.
  static List<RepaymentInstallment> generate({
    required String loanId,
    required DateTime startDate,
    required int duration,
    required double installmentAmount,
    required List<Holiday> holidays,
  }) {
    return _generateDaily(
      loanId: loanId,
      startDate: startDate,
      duration: duration,
      installmentAmount: installmentAmount,
      holidays: holidays,
    );
  }

  static List<RepaymentInstallment> _generateDaily({
    required String loanId,
    required DateTime startDate,
    required int duration,
    required double installmentAmount,
    required List<Holiday> holidays,
  }) {
    final schedule = <RepaymentInstallment>[];
    var currentDate = AppDateUtils.stripTime(startDate);
    var installmentsAdded = 0;

    while (installmentsAdded < duration) {
      // Find the next working day, including today if it's a working day
      currentDate = _findNextWorkingDay(currentDate, holidays);
      schedule.add(
        RepaymentInstallment(
          id: const Uuid().v4(),
          loanId: loanId,
          installmentNumber: installmentsAdded + 1,
          dueDate: currentDate,
          amount: installmentAmount,
        ),
      );
      installmentsAdded++;
      // Move to the next calendar day to start the search for the next installment
      currentDate = currentDate.add(const Duration(days: 1));
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
