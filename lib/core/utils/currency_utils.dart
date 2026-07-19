import 'package:intl/intl.dart';

import '../constants/app_constants.dart';

/// Currency formatting and parsing helpers. The default symbol/locale
/// come from [AppConstants], but every method accepts overrides so
/// screens can respect whatever currency is configured in the business's
/// financial settings (see
/// features/business/data/models/financial_settings_entity.dart) instead
/// of a single hard-coded currency for the whole app.
class CurrencyUtils {
  CurrencyUtils._();

  static const String defaultSymbol = AppConstants.defaultCurrencySymbol;
  static const String defaultLocale = AppConstants.defaultLocale;

  /// e.g. 12500.5 -> "$12,500.50"
  static String format(
    num amount, {
    String symbol = defaultSymbol,
    String locale = defaultLocale,
    int decimalDigits = 2,
  }) {
    return NumberFormat.currency(
      locale: locale,
      symbol: symbol,
      decimalDigits: decimalDigits,
    ).format(amount);
  }

  /// Compact form for dashboards / summary cards, e.g. 1250000 -> "$1.25M".
  static String formatCompact(
    num amount, {
    String symbol = defaultSymbol,
    String locale = defaultLocale,
  }) {
    return NumberFormat.compactCurrency(
      locale: locale,
      symbol: symbol,
    ).format(amount);
  }

  /// Plain thousands-separated number, no currency symbol.
  /// e.g. 12500.5 -> "12,500.50"
  static String formatNumber(num amount, {int decimalDigits = 2}) {
    return NumberFormat.decimalPattern().format(
      double.parse(amount.toStringAsFixed(decimalDigits)),
    );
  }

  /// Parses a user-typed or formatted currency string back into a double,
  /// stripping currency symbols, thousands separators, and whitespace.
  /// Returns `null` if nothing numeric could be found.
  ///
  /// e.g. "$12,500.50" -> 12500.5, "12500" -> 12500.0
  static double? parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^\d.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Rounds to 2 decimal places — the precision expected for currency
  /// amounts stored in the database.
  static double roundToCents(num amount) => (amount * 100).round() / 100;

  /// e.g. (25, 200) -> "12.5%"
  static String formatPercentage(num part, num whole, {int decimalDigits = 1}) {
    if (whole == 0) return '0%';
    return '${((part / whole) * 100).toStringAsFixed(decimalDigits)}%';
  }

  /// e.g. 5.0 -> "5.0%" — for displaying an already-computed rate rather
  /// than deriving one from two amounts.
  static String formatRate(num rate, {int decimalDigits = 1}) =>
      '${rate.toStringAsFixed(decimalDigits)}%';

  /// Splits [total] into [parts] equal installments, distributing any
  /// rounding remainder (in cents) across the first few installments so
  /// the sum of the returned list always exactly equals [total]. This
  /// matters for repayment schedules — silently dropping a rounding
  /// error into the last installment is a common source of "why is my
  /// loan balance off by a cent" bugs.
  static List<double> splitEvenly(double total, int parts) {
    if (parts <= 0) return const [];
    final totalCents = (total * 100).round();
    final baseCents = totalCents ~/ parts;
    final remainder = totalCents - (baseCents * parts);

    return List.generate(parts, (i) {
      final cents = baseCents + (i < remainder ? 1 : 0);
      return cents / 100;
    });
  }
}
