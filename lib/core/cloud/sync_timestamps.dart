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
String syncTimestamp([DateTime? value]) {
  final now = (value ?? DateTime.now()).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}'
      'T${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
      '.${three(now.millisecond)}Z';
}
