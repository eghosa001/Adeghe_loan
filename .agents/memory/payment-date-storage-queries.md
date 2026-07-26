---
name: Payment date storage vs. queries
description: Keep stored payment dates and date-range queries in the same format to avoid off-by-one-day bugs.
---

If `payment_date` is stored as a full ISO-8601 timestamp (`2026-07-26T12:00:00`) but the report query uses `BETWEEN '2026-07-01' AND '2026-07-31'`, records on the final day that have a time component are excluded because the timestamp is lexicographically greater than the bare date string.

**Why:** SQLite compares strings lexicographically when given string values. `'2026-07-31 10:00' > '2026-07-31'`.

**How to apply:** Choose one strategy consistently:
- **Storage strategy:** Store dates as `yyyy-MM-dd` (e.g., via `AppDateUtils.formatForStorage`) and use bare `yyyy-MM-dd` in `BETWEEN`.
- **Query strategy:** If timestamps are stored, append ` 23:59:59` to the end date in the query so the full final day is included.

Prefer the storage strategy because it matches how other app tables (`loans.loan_date`, etc.) store dates.
