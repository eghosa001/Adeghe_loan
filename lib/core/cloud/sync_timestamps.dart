/// Shared clock for cloud-sync change tracking.
///
/// Every `updated_at` value (trigger stamps, migration back-fills, sync
/// watermarks) MUST use this exact fixed-width format:
/// `yyyy-MM-ddTHH:mm:ss.SSSZ` (UTC, 3-digit milliseconds, trailing Z).
///
/// Sync relies on lexicographic string comparison as a stand-in for
/// chronological order (last-write-wins). Any deviation — e.g. `toIso8601String()`
/// emitting 6-digit microseconds — breaks that ordering between rows written by
/// different mechanisms.
///
/// Runtime-generated timestamps are also kept strictly increasing within this
/// process. SQLite/OS clocks can return the same millisecond for several writes
/// (or move backwards after a clock adjustment); without a monotonic floor,
/// two successive local updates can receive the same/older `updated_at` and a
/// later cloud pull can incorrectly discard the newer write as an LWW tie.
DateTime? _lastRuntimeTimestamp;

String syncTimestamp([DateTime? value]) {
  var now = (value ?? DateTime.now()).toUtc();

  // Explicit values are used for deterministic migrations/backfills and must
  // remain exact. Only timestamps generated from the runtime clock participate
  // in the monotonic sequence.
  if (value == null) {
    final last = _lastRuntimeTimestamp;
    if (last != null && !now.isAfter(last)) {
      now = last.add(const Duration(milliseconds: 1));
    }
    _lastRuntimeTimestamp = now;
  }

  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}'
      'T${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '.${three(now.millisecond)}Z';
}
