import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Date helpers used throughout the app — display formatting, parsing,
/// and the calendar math loan repayment schedules need (adding months
/// without overflowing into the wrong month, counting days between two
/// dates, skipping weekends, etc).
///
/// Named `AppDateUtils` rather than `DateUtils` to avoid colliding with
/// Flutter's own `material.dart` class of that name.
class AppDateUtils {
  AppDateUtils._();

  static final DateFormat _displayFormat =
      DateFormat(AppConstants.dateFormatDisplay);
  static final DateFormat _apiFormat = DateFormat(AppConstants.dateFormatApi);
  static final DateFormat _displayDateTimeFormat =
      DateFormat(AppConstants.dateTimeFormatDisplay);

  // ---------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------

  /// e.g. "15 Jul 2026"
  static String formatDate(DateTime date) => _displayFormat.format(date);

  /// e.g. "2026-07-15" — used for DB storage / sorting.
  static String formatForStorage(DateTime date) => _apiFormat.format(date);

  /// e.g. "15 Jul 2026, 02:30 PM"
  static String formatDateTime(DateTime date) =>
      _displayDateTimeFormat.format(date);

  /// e.g. "02:30 PM"
  static String formatTime(DateTime date) => DateFormat('hh:mm a').format(date);

  /// Human-friendly relative label — "Today", "Yesterday", "Tomorrow",
  /// "in 3 days", "3 days ago" — falling back to [formatDate] outside a
  /// 7-day window.
  static String formatRelative(DateTime date) {
    final today = stripTime(DateTime.now());
    final target = stripTime(date);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    if (diff > 1 && diff <= 7) return 'in $diff days';
    if (diff < -1 && diff >= -7) return '${diff.abs()} days ago';
    return formatDate(date);
  }

  // ---------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------

  /// Parses a value written in [AppConstants.dateFormatApi], falling back
  /// to [DateTime.tryParse] for ISO-8601 strings (e.g. values coming from
  /// a restored backup file). Returns `null` for anything unparseable.
  static DateTime? tryParseStorage(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return _apiFormat.parseStrict(value);
    } catch (_) {
      return DateTime.tryParse(value);
    }
  }

  // ---------------------------------------------------------------------
  // Normalization
  // ---------------------------------------------------------------------

  /// Midnight of the given date, so two [DateTime]s on the same calendar
  /// day compare as equal regardless of their time component.
  static DateTime stripTime(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime startOfDay(DateTime date) => stripTime(date);

  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month, 1);

  /// Last instant of the month — relies on `day: 0` rolling back to the
  /// final day of the previous month, which also correctly handles
  /// December (`month: 13` rolls forward into January of next year first).
  static DateTime endOfMonth(DateTime date) =>
      DateTime(date.year, date.month + 1, 0, 23, 59, 59, 999);

  static DateTime startOfWeek(DateTime date,
      {int firstDayOfWeek = DateTime.monday}) {
    final stripped = stripTime(date);
    final diff = (stripped.weekday - firstDayOfWeek) % 7;
    return stripped.subtract(Duration(days: diff));
  }

  // ---------------------------------------------------------------------
  // Comparisons
  // ---------------------------------------------------------------------

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime date) => isSameDay(date, DateTime.now());

  static bool isPast(DateTime date) =>
      stripTime(date).isBefore(stripTime(DateTime.now()));

  static bool isFuture(DateTime date) =>
      stripTime(date).isAfter(stripTime(DateTime.now()));

  static bool isWeekend(DateTime date) =>
      date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  /// Whole days between [from] and [to] (ignoring time-of-day), positive
  /// when [to] is after [from].
  static int daysBetween(DateTime from, DateTime to) =>
      stripTime(to).difference(stripTime(from)).inDays;

  // ---------------------------------------------------------------------
  // Loan-schedule math
  // ---------------------------------------------------------------------

  /// Adds [months] calendar months to [date] (negative values go
  /// backward), clamping the day-of-month so e.g. 31 Jan + 1 month lands
  /// on 28/29 Feb instead of rolling into March. Uses floor division so
  /// it's also correct for negative offsets that cross a year boundary
  /// (e.g. 15 Jan − 1 month = 15 Dec of the *previous* year — a plain
  /// `~/` would get this wrong since it truncates toward zero).
  static DateTime addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final monthMod = totalMonths % 12; // Dart's % is Euclidean: always 0..11
    final year = date.year + (totalMonths - monthMod) ~/ 12;
    final month = monthMod + 1;
    final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
    final day =
        date.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : date.day;
    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }

  /// Thin, explicit wrapper over [Duration] for weekly repayment
  /// schedules, kept separate from [addMonths] for readability at call
  /// sites.
  static DateTime addWeeks(DateTime date, int weeks) =>
      date.add(Duration(days: weeks * 7));
}
