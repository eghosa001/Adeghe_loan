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
  ///
  /// - For [LoanType.daily], it counts forward [duration] working days.
  /// - For [LoanType.monthly], it advances month-by-month, shifting any due
  ///   date that falls on a non-working day to the next available working day.
  static List<RepaymentInstallment> generate({
    required String loanId,
    required LoanType loanType,
    required DateTime startDate,
    required int duration, // Days for Daily, Months for Monthly
    required double installmentAmount,
    required List<Holiday> holidays,
  }) {
    if (loanType == LoanType.daily) {
      return _generateDaily(
        loanId: loanId,
        startDate: startDate,
        duration: duration,
        installmentAmount: installmentAmount,
        holidays: holidays,
      );
    } else {
      // Monthly
      return _generateMonthly(
        loanId: loanId,
        startDate: startDate,
        duration: duration,
        installmentAmount: installmentAmount,
        holidays: holidays,
      );
    }
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

  static List<RepaymentInstallment> _generateMonthly({
    required String loanId,
    required DateTime startDate,
    required int duration,
    required double installmentAmount,
    required List<Holiday> holidays,
  }) {
    final schedule = <RepaymentInstallment>[];
    for (var i = 1; i <= duration; i++) {
      // Calculate the base due date for the month
      var dueDate = AppDateUtils.addMonths(startDate, i);
      // Adjust if it falls on a non-working day
      dueDate = _findNextWorkingDay(dueDate, holidays);
      schedule.add(
        RepaymentInstallment(
          id: const Uuid().v4(),
          loanId: loanId,
          installmentNumber: i,
          dueDate: dueDate,
          amount: installmentAmount,
        ),
      );
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
