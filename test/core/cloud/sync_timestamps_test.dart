import 'package:flutter_test/flutter_test.dart';

import 'package:loantrack/core/cloud/sync_timestamps.dart';

void main() {
  test('runtime sync timestamps are strictly increasing', () {
    final values = List.generate(100, (_) => syncTimestamp());

    for (var i = 1; i < values.length; i++) {
      expect(values[i].compareTo(values[i - 1]), greaterThan(0));
    }
  });

  test('explicit sync timestamp remains deterministic', () {
    final value = DateTime.utc(2026, 9, 5, 12, 34, 56, 789);
    expect(syncTimestamp(value), '2026-09-05T12:34:56.789Z');
  });
}
