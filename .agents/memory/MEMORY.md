# Memory

- [Google Fonts Flutter compatibility](google-fonts-flutter-compat.md) — old `google_fonts` versions break with Flutter 3.44+; upgrade SDK + package together.
- [SQLite DROP COLUMN portability](sqlite-drop-column-compat.md) — `ALTER TABLE DROP COLUMN` fails on older Android SQLite; recreate table instead.
- [Payment date storage vs. queries](payment-date-storage-queries.md) — store dates in `yyyy-MM-dd` or adjust range queries for full-day inclusion.
- [DropdownButtonFormField deprecation](dropdown-form-field-deprecation.md) — `value` is deprecated in Flutter 3.33+; use `initialValue`.
- [Web preview limits](web-preview-limits.md) — `sqflite_sqlcipher` does not support web; web preview is UI-only.
