# AGENTS.md — Adeghe Professional Services

## Project overview

Offline-first Flutter loan/microfinance management app targeting the Nigerian market. Encrypted local SQLite database, PIN + biometric auth, optional Supabase cloud sync.

**Package name:** `loantrack` (repository root is `loan_application`)
**App name:** Adeghe Professional Services
**App creator:** AIGHEWI EGHOSA

## Commands

```bash
flutter run                        # Run the app
flutter test                       # Run all tests
flutter test test/widget_test.dart # Run a single test file
flutter analyze                    # Static analysis
flutter build apk                  # Android release build
flutter build windows --release    # Windows desktop build
```

No Makefile, scripts, or CI workflows exist. No custom lint rules beyond default `flutter_lints`. No codegen — all serialization is manual `toMap()`/`fromMap()`.

## Architecture

**Pattern:** Feature-first folder structure with Riverpod for state/DI, GoRouter for navigation.

```
lib/
  main.dart                        # Entry point: ProviderScope -> MyApp
  core/
    constant/app_constants.dart
    database/database_service.dart  # Encrypted SQLite (sqflite_sqlcipher)
    di/providers.dart               # Central Riverpod providers
    router/app_router.dart          # GoRouter config
    security/                       # Biometric, file encryption, secure storage
    services/                       # Backup, document, export services
    theme/app_theme.dart
    utils/                          # Currency, date, inactivity wrapper
  features/
    auth/           # PIN-based auth + biometrics
    business/       # Business profile, financial settings, backup
    customers/      # CRUD with search
    documents/      # Encrypted customer documents (AES-GCM)
    holidays/       # Holiday management for schedule generation
    loans/          # Loan creation, schedule generation, calculator
    payments/       # Payment recording
    savings/        # Customer savings
    reports/        # Dashboard + sub-reports
    collection/     # Daily/weekly collection screens
    groups/         # Customer groups
    settings/       # App settings, cloud sync
    search/         # Global search
    dashboard/      # Home screen
    notifications/  # Notification bell + list
    audit_log/      # Audit trail
```

**State management:** Riverpod v2 — `Provider`, `FutureProvider`, `StateProvider`, `StateNotifierProvider`. Screens use `ConsumerWidget`/`ConsumerStatefulWidget`.

**Database:** `sqflite_sqlcipher` — encrypted SQLite. DB file: `loantrack.db`. Key stored in FlutterSecureStorage. Schema version 24 with manual ALTER TABLE + table-recreate migrations in `migrations.dart` (`database_service.dart` holds the fresh-install CREATE SQL and the version constant — keep both in sync). `PRAGMA foreign_keys = ON` is enforced.

**Cloud sync (Supabase):** Optional offline-first replication. Local SQLite is source of truth. Max two owners (email allow-list + RLS). `supabase_schema.sql` must mirror local schema. Documents are end-to-end encrypted before upload.

## Critical business rules (DO NOT CHANGE without owner decision)

### Money rule (NON-NEGOTIABLE)

Every aggregate over payments MUST:
1. Filter `p.status = 'completed'` (never sum reversed payments), AND
2. Subtract savings overpayments: `(p.amount - COALESCE(st.amount, 0.0))` via
   `LEFT JOIN savings_transactions st ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'`.

Reference pattern: `lib/features/payments/data/payment_repository.dart` `_recalculateScheduleFromPayments` and `lib/features/reports/data/report_repository.dart` query #6.

**Savings are NEVER included in "Total Collected" / "Total Paid" / any collected-total.** The `- COALESCE(st.amount, 0.0)` subtraction intentionally excludes the savings overpayment surplus. This was the owner's explicit decision; reverting it is a regression.

### Overpayment → savings mechanism

Excess over the current installment is ALWAYS credited to the customer's savings account; it is never applied past the installment to the loan.

- Split rule (`computePaymentSplit`, `lib/features/payments/data/payment_logic.dart`):
  - `cap = (installmentDue != null && installmentDue > 0) ? installmentDue : outstandingBalance`
  - `loanPaid = min(paymentAmount, cap)`
  - `surplus = paymentAmount - loanPaid`
  - `newBalance = max(0, outstandingBalance - loanPaid)`
- The surplus is stored as a `savings_transactions` row with `type = 'overpayment'`, POSITIVE `amount`, and `reference_loan_payment_id = <payment id>`.
- `repayment_schedule.paid_amount` must ONLY ever reflect loan-applied amounts.

### Loan types

- **Daily loans:** 1 installment per day, 6 days/week (Mon–Sat), Sunday excluded.
- **Weekly loans:** 1 installment per week, fixed weekday.
- Holidays skip both daily and weekly installments.
- A customer holding both a daily and a weekly loan counts ONCE in any "customers" figure (`COUNT(DISTINCT customer_id)`).

### Customer counts

Customer counts are distinct across loan types. Any "customers" figure must be `COUNT(DISTINCT customer_id)`.

### Collections

- Collection totals: due = unpaid portion of due installments; paid excludes reversed/overpayments.
- Payment application order is oldest-first.
- Weekly collection display is installment-WEEK attribution (the week the money PAYS FOR), not the payment arrival date. A weekly row is tied to its in-range installment; `collectedThisPeriod` = that installment's schedule `paid_amount` (money-rule safe). A late payment for an older missed installment lights up THAT installment's week, never the week the money arrived.
- Daily collection has NO Saturday/Sunday rows. A payment received Sat/Sun counts on the PRECEDING Friday ("as monday is a new week"), so Friday absorbs Fri + Sat + Sun; a range attributes payments by that same weekend→Friday rule.

## Important invariants (AI must not break these)

- **No codegen:** Do not add `build_runner`, `freezed`, or `json_serializable`. Keep manual `toMap()`/`fromMap()`.
- **SQL names:** never interpolate table/column names not in the schema (`database_service.dart` + `migrations.dart`). `customers` uses `date_registered`, NOT `created_at`. `test/database/schema_crosscheck_test.dart` enforces this.
- **Dynamic calls:** do not use `(x as dynamic).member`. Entity fields must be real fields.
- **Destructive I/O:** never delete the live DB before verifying a backup (temp-write → verify → atomic swap). Backups must include `secure_documents/`.
- **Settings:** every setting persisted must have a real consumer (session-timeout → `InactivityWrapper`; auto-backup → `BackupService.maybeAutoBackup`; currency → `currencySymbolProvider`).
- **Dates:** `payment_date`/`due_date` are stored `yyyy-MM-dd` local strings; `savings_transactions.created_at` is ISO-8601 (`T`). Never use `date('now')` (UTC) — pass the Dart local date.
- **Schedule money:** use `CurrencyUtils.splitEvenly` for installment rounding so Σ installments == `total_repayment`; a loan must be able to reach `completed`.
- **Numeric safety:** all financial inputs must be finite and non-negative. Use `CurrencyUtils.tryParseAmount` / `tryParsePositiveAmount`. Durations are capped at `AppConstants.maxLoanDuration` (365).
- **Document encryption:** acceptance is by content, not extension — magic-byte check at upload. Decryption re-verifies content MIME from bytes, never stored metadata.
- **PIN/recovery:** PIN uses salted PBKDF2-HMAC-SHA256 (120k iters); recovery password uses 600k iters, min 16 chars with letters AND digits.
- **Biometric grants do NOT persist across backgrounding.**
- **Notifications:** badge only on Dashboard AppBar; reachable from every screen via AppDrawer. Never a floating button.

## Testing

```bash
flutter test                                     # Full suite
flutter test test/database/schema_crosscheck_test.dart   # SQL-name guard
flutter test test/auth/pin_lockout_service_test.dart     # PIN lockout
flutter test test/core/router_auth_guard_test.dart       # Auth redirect
flutter test test/backup/backup_service_test.dart        # Safe restore
flutter test test/payments/repayment_integration_audit_test.dart  # Repayment end-to-end
```

Keep all tests — they protect financial calculations. Tests are in `test/` and use `flutter_test`.

## File conventions

- **Migrations:** `lib/core/database/migrations.dart`. Fresh-install DDL + `_databaseVersion` in `database_service.dart` — keep both in sync.
- **Supabase schema:** `supabase_schema.sql` must mirror local schema. Any table/column change must be added there AND to `_syncTables`/`_tablePrimaryKeys` in `cloud_sync_service.dart`.
- **Sync timestamps:** MUST use `syncTimestamp()` (`sync_timestamps.dart`) — `yyyy-MM-ddTHH:mm:ss.SSSZ` UTC with 3-digit millis. Lexicographic LWW depends on this format.
- **Windows build:** `windows/installer/setup.iss` (Inno Setup 6). Output: `build/installer/AdegheProfessionalServices-Setup-<ver>.exe`.
