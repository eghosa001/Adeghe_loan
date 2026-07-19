import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// The shared Logger instance used by providers that need a pretty-printed logger.
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.none,
  ),
);

/// Lightweight, dependency-free logging wrapper used across the app.
///
/// This is a *developer* logger for debugging (console + DevTools), not
/// the business-level audit trail — for "who did what to which loan and
/// when", see features/audit_log (Part 6), which persists structured
/// entries to the database instead of the console.
enum LogLevel { debug, info, warning, error }

class AppLogger {
  AppLogger._();

  /// Set to `false` to silence [debug]/[info] logs even in a build where
  /// `kDebugMode` checks are bypassed elsewhere. Defaults to mirroring
  /// `kDebugMode`.
  static bool verbose = kDebugMode;

  /// Keeps the most recent log lines in memory so a "Send diagnostics" /
  /// bug-report screen can attach recent activity without needing to
  /// grep device logs.
  static final List<String> _recentLogs = [];
  static const int _maxRecentLogs = 200;

  static void debug(String message, {String tag = 'App'}) =>
      _log(LogLevel.debug, tag, message);

  static void info(String message, {String tag = 'App'}) =>
      _log(LogLevel.info, tag, message);

  static void warning(String message, {String tag = 'App'}) =>
      _log(LogLevel.warning, tag, message);

  static void error(
    String message, {
    String tag = 'App',
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);

  static void _log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!verbose && level != LogLevel.error) return;

    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] ${level.name.toUpperCase()} [$tag] $message';

    _recentLogs.add(line);
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    developer.log(
      message,
      time: DateTime.now(),
      name: tag,
      level: _severityFor(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  static int _severityFor(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warning => 900,
        LogLevel.error => 1000,
      };

  /// A snapshot of the most recent in-memory log lines, newest last.
  static List<String> get recentLogs => List.unmodifiable(_recentLogs);

  static void clearRecentLogs() => _recentLogs.clear();
}
