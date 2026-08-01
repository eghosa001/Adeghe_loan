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

  /// Short compact form for chart axis labels, e.g. 1250000 -> "1.25M".
  static String formatShort(num amount) {
    return NumberFormat.compact().format(amount);
  }

  /// Rounds to 2 decimal places — the precision expected for currency
  /// amounts stored in the database.
  static double roundToCents(num amount) => (amount * 100).round() / 100;

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
