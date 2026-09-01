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

  /// Converts a currency amount to integer minor units (kobo/cents).
  /// Financial arithmetic can use these exact integers instead of doubles.
  static int toMinorUnits(num amount) {
    if (!amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'must be finite');
    }
    final scaled = amount * 100;
    if (!scaled.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'is too large');
    }
    return scaled.round();
  }

  static double fromMinorUnits(int amount) => amount / 100.0;

  static int? tryParseMinorUnits(String? text) {
    final value = tryParseAmount(text);
    return value == null ? null : toMinorUnits(value);
  }

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

  static double roundToCents(num amount) {
    if (!amount.isFinite) return 0;
    final scaled = amount * 100;
    if (!scaled.isFinite) return amount.toDouble();
    return scaled.round() / 100;
  }

  /// Splits a total into exact cent-sized installments where possible.
  static List<double> splitEvenly(double total, int parts) {
    if (parts <= 0 || !total.isFinite) return const [];
    final totalCents = toMinorUnits(total);
    final baseCents = totalCents ~/ parts;
    final remainder = totalCents - (baseCents * parts);
    return List<double>.generate(parts, (i) {
      final cents = baseCents + (i < remainder ? 1 : 0);
      return fromMinorUnits(cents);
    });
  }

  /// Parses [text] as a finite, non-negative number, or returns null.
  static double? tryParseAmount(String? text) {
    final v = double.tryParse((text ?? '').trim());
    return (v != null && v.isFinite && v >= 0) ? v : null;
  }

  /// Parses [text] as a finite, strictly positive number, or returns null.
  static double? tryParsePositiveAmount(String? text) {
    final v = tryParseAmount(text);
    return (v != null && v > 0) ? v : null;
  }
}
