---
name: SQLite DROP COLUMN portability
description: Why ALTER TABLE DROP COLUMN is unsafe for Android SQLite and the safe migration pattern.
---

`ALTER TABLE ... DROP COLUMN` is only supported in SQLite 3.35.0+. Many Android devices ship with older SQLite versions, so a migration using `DROP COLUMN` will crash on those devices during app upgrade.

**Why:** SQLite's `ALTER TABLE DROP COLUMN` is a relatively recent feature. The cross-platform safe approach is the classic table-recreate pattern.

**How to apply:** When a migration needs to remove columns, instead of `DROP COLUMN`:
1. Create a new table with the desired schema.
2. Copy the needed columns from the old table into the new table.
3. Drop the old table.
4. Rename the new table to the original name.
5. Recreate any indexes that were dropped with the old table.

This pattern works on every SQLite version that Flutter supports.
