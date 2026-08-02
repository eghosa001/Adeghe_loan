# AGENTS.md — Adeghe Professional Services

## Project overview

Offline-first Flutter loan/microfinance management app targeting the Nigerian market. Encrypted local SQLite database, PIN + biometric auth, no backend server.

**Package name:** `loantrack` (repository root is `loan_application`)

`App name:` **Adeghe Professional Services**

`App creator:` **AIGHEWI EGHOSA**

## Commands

```bash
flutter run                        # Run the app
flutter test                       # Run all tests
flutter test test/widget_test.dart # Run a single test file
flutter analyze                    # Static analysis
flutter build apk                  # Android release build
dart run build_runner build --delete-conflicting-outputs  # Codegen (currently unused — see below)
```

No Makefile, scripts, or CI workflows exist. No custom lint rules beyond default `flutter_lints`.

## Architecture

**Pattern:** Feature-first folder structure with Riverpod for state/DI, GoRouter for navigation.

```
lib/
  main.dart                        # Entry point: ProviderScope -> MyApp
  core/
    constant/app_constants.dart
    database/database_service.dart  # Encrypted SQLite (sqflite_sqlcipher), 9 tables, migrations v1-v16
    di/providers.dart               # Central Riverpod providers
    router/app_router.dart          # GoRouter config; some screens defined inline
    security/                       # Biometric, file encryption, secure storage
    services/                       # Backup, document, export services
    theme/app_theme.dart
    utils/                          # Currency, date, inactivity wrapper
  features/
    auth/       # PIN-based auth + biometrics; auth_provider.dart is the StateNotifier
    business/   # Business profile, financial settings, backup
    customers/  # CRUD with search
    documents/  # Encrypted customer documents (AES-GCM)
    holidays/   # Holiday management for schedule generation
    loans/      # Loan creation, schedule generation, calculator
    payments/   # Payment recording
```

**Routing:** GoRouter in `lib/core/router/app_router.dart`. Initial route `/splash`. Uses `state.params['id']` for path params, `state.extra` for objects.

**State management:** Riverpod v2 — `Provider`, `FutureProvider`, `StateProvider`, `StateNotifierProvider`. Screens use `ConsumerWidget`/`ConsumerStatefulWidget`.

**Database:** `sqflite_sqlcipher` — encrypted SQLite. DB file: `loantrack.db`. Key stored in FlutterSecureStorage. Schema version 16 with manual ALTER TABLE + table-recreate migrations in `migrations.dart` (`database_service.dart` holds the fresh-install CREATE SQL and the version constant — keep both in sync). **Note:** `PRAGMA foreign_keys = ON` is enforced.

**Auth:** Local-only. PIN (salted PBKDF2-HMAC-SHA256, 120k iterations, stored as `pbkdf2-sha256:<iterations>:<base64>`) + optional biometrics. 5-minute auto-lock via `InactivityWrapper` (pointer events + hardware keyboard). `databaseServiceProvider` polls `authProvider` until unlocked before initializing DB.

**Document encryption:** `FileEncryptionService` — `[LTD1 header][12-byte IV][AES-GCM ciphertext]`. Max 20 MB. Supported: PDF, PNG, JPG.

**Error handling:** Sealed `Result<T>` type (`Success<T>` / `ResultError<T>`) with 11 `Failure` subtypes. No exceptions across repository boundaries.

**Entities:** Hand-written `toMap()`/`fromMap()` methods. No code-generated serialization despite dev dependencies.

## Code generation

`build_runner`, `freezed`, `json_serializable` are declared in `pubspec.yaml` but **completely unused**. No `.g.dart` or `.freezed.dart` files exist. No `build.yaml`. All serialization is manual.

## Testing

Tests in `test/`. Uses `flutter_test`. `mocktail` is a dev dependency but unused.

```bash
flutter test                                     # Full suite
flutter test test/database/schema_crosscheck_test.dart   # SQL-name guard
flutter test test/auth/pin_lockout_service_test.dart     # PIN lockout
flutter test test/core/router_auth_guard_test.dart       # Auth redirect
flutter test test/backup/backup_service_test.dart        # Safe restore
```

## Money rule (NON-NEGOTIABLE)

Every aggregate over payments MUST:
1. Filter `p.status = 'completed'` (never sum reversed payments), AND
2. Subtract savings overpayments: `(p.amount - COALESCE(st.amount, 0.0))` via
   `LEFT JOIN savings_transactions st ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'`.

Reference pattern: `lib/features/payments/data/payment_repository.dart` `_recalculateScheduleFromPayments` and `lib/features/reports/data/report_repository.dart` query #6. A new `SUM(p.amount` without this pattern is a bug.

**Owner decision (DO NOT REVERT):** Savings are NEVER included in "Total Collected" / "Total Paid" / any collected-total. The `- COALESCE(st.amount, 0.0)` subtraction above intentionally excludes the savings overpayment surplus so collected-totals reflect only money applied to loans (recorded in `savings_transactions`). This was the owner's explicit decision (2026-08-01); treating the subtraction as a bug and re-adding savings to collected totals is a regression.

**Overpayment → savings mechanism (lock-in, 2026-08-01):** Excess over the current installment is ALWAYS credited to the customer's savings account; it is never applied past the installment to the loan. This only changes if a proven bug exists.

- Split rule (`computePaymentSplit`, `lib/features/payments/data/payment_logic.dart`): `cap = (installmentDue != null && installmentDue > 0) ? installmentDue : outstandingBalance`; `loanPaid = min(paymentAmount, cap)`; `surplus = paymentAmount - loanPaid`; `newBalance = max(0, outstandingBalance - loanPaid)`.
- Callers pass the installment context into `PaymentRepository.createPayment({..., double? installmentDue})`: `collection_screen.dart` passes `installmentAmount - amountPaid`; `future_schedule_screen.dart` passes the row's `amountDue`; `record_payment_screen.dart` forwards the value routed from `loan_details_screen.dart`. Omitted/zero → the payment caps at the outstanding balance (settlements / quick-pay apply fully to the loan).
- Storage order: the `payments` row is inserted BEFORE the savings transaction. The surplus is stored as a `savings_transactions` row with `type = 'overpayment'`, a POSITIVE `amount`, and `reference_loan_payment_id = <payment id>`. The loan-applied portion is NOT persisted; it is derived as `payment.amount − surplus`.
- Reversal (`reversePayment`) reads the linked `overpayment` row back, restores `max(0, amount − surplus)` to the loan, and debits savings by `min(surplus, balance)` with a `type = 'withdrawal'` reversal row. A `clearLoanWithSavings` payment's linked `type = 'withdrawal'` row is refunded as a `type = 'deposit'` row so the savings balance is conserved across the full round trip.
- `repayment_schedule.paid_amount` must ONLY ever reflect loan-applied amounts (`_recalculateScheduleFromPayments` recomputes it from the money rule).

## Product decisions (lock-in, 2026-08-01)

- **Notification bell:** displayed only on the Dashboard AppBar (badge when count > 0). Notifications stay reachable from every screen via the AppDrawer. It must never render as a floating button that can overlap pushed screens (e.g. "Add Customer").
- **Reports screen:** contains ONLY the five tabs — Overview, Daily, Weekly, Overdue, Analytics. No filter chips, no loan-type SegmentedButton, no custom date-range picker (report period defaults to this month; see `reportStartDateProvider`/`reportEndDateProvider`).
- **Customer counts are distinct:** a customer holding both a daily and a weekly loan counts ONCE, not per loan. Any "customers" figure must be `COUNT(DISTINCT customer_id)` (or distinct in Dart) across loan types.
- **Savings report:** totals are across ALL customers (net savings held). Per-customer statements live in the savings statement screen / Excel export.
- **Customer list keeps groups:** the customer list screen keeps the group filter chips (All / each group) PLUS a "No group" chip (via `ungroupedGroupFilter` in `customer_repository.dart`, matching `COALESCE(c.group_id, '') = ''`), and the "Sort by Group" option (`CustomerSortOption.group`). Groups are never removed from the customer list — the "no group" view exists so ungrouped customers can be found deliberately.

## Recurrence-prevention rules

- **SQL names:** never interpolate table/column names that are not in the schema (`database_service.dart` + `migrations.dart`). The `customers` table uses `date_registered`, NOT `created_at`. `test/database/schema_crosscheck_test.dart` parses every `rawQuery`/`query`/`execute` SQL string in `lib/` plus `insert('table', …)` first args and fails if a table, `alias.column`, or bare column is missing from the schema (skips DDL).
- **Dynamic calls:** do not use `(x as dynamic).member` — enable `avoid_dynamic_calls` in analysis. `Loan.customerName` must be a real field.
- **Destructive I/O:** never delete the live DB before verifying a backup (temp-write → verify → atomic swap). Backups must include `secure_documents/`.
- **Settings:** every setting persisted must have a real consumer (session-timeout → `InactivityWrapper`; auto-backup → `BackupService.maybeAutoBackup`; currency → `currencySymbolProvider`).
- **Dates:** `payment_date`/`due_date` are stored `yyyy-MM-dd` local strings; `savings_transactions.created_at` is ISO-8601 (`T`). Never compare the ISO timestamp with a `'… 23:59:59'` (space) bound — use date-only bounds. Never use `date('now')` (UTC) against local dates — pass the Dart local date.
- **Schedule money:** use `CurrencyUtils.splitEvenly` (currency_utils.dart) for installment rounding so Σ installments == `total_repayment`; a loan must be able to reach `completed`.

## Gotchas and known issues (live bug log — from AUDIT_PLAN.md audit 2026-07-31)

Verified fixed (Phase 0, 2026-07-31 — all items from the audit have been addressed):
- **C1** loan-list crash (`Loan.customerName` field + `loan_list_screen.dart`; tests `test/loans/loan_entity_test.dart`).
- **C2** analytics `customers.created_at` → `DATE(date_registered)` (report_repository; mutation-tested in schema crosscheck).
- **C3** auto-lock (`main.dart` lifecycle observer + router auth redirect; tests `test/core/router_auth_guard_test.dart`).
- **C4** restore deletes live DB before validating backup (safe swap in `backup_service.dart`; tests `test/backup/backup_service_test.dart`).
- **C5** PIN lockout (`pin_lockout_service.dart` + abstract `SecureKeyValueStore`; tests `test/auth/pin_lockout_service_test.dart`).
- **H1** multi-installment/pay-in-full payments now cap at outstanding balance, only the excess goes to savings (`payment_logic.dart` `computePaymentSplit`; tests `test/payments/payment_logic_test.dart`).
- **H2/H3** schedule sum == `total_repayment` via `CurrencyUtils.splitEvenly`; edits regenerate schedule + honor `customCollectionAmount` (`loan_providers.dart`).
- **H4** loan list no longer capped (`loan_repository.dart` `getAllLoans(limit:)` default null).
- **H5** collection range totals: due = unpaid portion of due installments; paid excludes reversed/overpayments (`collection_repository.dart`).
- **H6/H7/H8** client report totalPaid follows the money rule; end-of-month savings rows use date-only bounds; cancelled loans excluded from disbursed/interest/fees/expected (`report_repository.dart`).
- **H9/H14** session-timeout + auto-backup settings now have real consumers (`main.dart` `InactivityWrapper` timeout; `BackupService.maybeAutoBackup()` on unlock).
- **H10** PIN/recovery hashing is salted PBKDF2-HMAC-SHA256 (120k iters); `keyPinSalt` used (`secure_storage_service.dart`).
- **H11** `/documents/preview` guards non-`CustomerDocument` `state.extra` (`app_router.dart`).
- **H12/H13/M15/M16** forgot-PIN/change-PIN use `PinLockoutService`; recovery password ≥8 chars; PIN-setup cancels cleanly; biometric enable requires a successful auth (`security_settings_screen.dart`, `pin_setup_screen.dart`).
- **M1** reversal restores the exact pre-payment loan status via stored `payments.prior_loan_status` (defaulted loans no longer flip to active).
- **M2/M5** report loan-type filter flows UI → provider → repository; overdue = unpaid installments with `DATE(due_date) < today` (count and list agree).
- **M3/M4** savings aggregates exclude reversed payments and include `'overpayment'` type.
- **M6/M8** dashboard uses Dart-local dates (no `date('now')`) and excludes reversed payments.
- **M7** legacy `loan_type='monthly'` rows migrated to `'weekly'` (v15 migration).
- **M9** report total customers is a distinct count, not `daily+weekly` (`report_screen.dart` uses `summary.totalCustomers`).
- **M10** currency is read from settings (`currencySymbolProvider`); search/notifications/collection/payment/savings UIs no longer hard-code `₦`.
- **M11** `decryptFile` throws typed `FileEncryptionException` for read/corrupt-file cases (`file_encryption_service.dart`).
- **M12** backups are ZIP containers that include `secure_documents/`; legacy raw-DB restore still accepted (`backup_service.dart`).
- **M13** notification queries filter `l.status = 'active'`.
- **M17** `InactivityWrapper` covers pointer down/move/signal + hardware keyboard.
- **M18/M19** loan form state resets after save; `saveLoan`/`updateLoan` surface `Result.failure`.
- **M20/M21** "Share statement" produces a PDF via `StatementService.buildCustomerStatementPdf` + `SharePlus`; statements include non-active loans (`loan_statement_screen.dart`).
- **M22** customer delete is a soft archive (`customers.status = 'archived'`); loans/payments/documents/history are preserved (`customer_repository.dart`).
- **L1** export filenames get a unique timestamp suffix — same-day exports no longer overwrite (`export_manager.dart`, `excel_export_service.dart`).
- **L2** group-delete undo restores the recreated group's membership (`group_repository.dart` returns member ids; `group_management_screen.dart` reassigns them).
- **L3/L4** holiday date parse falls back to epoch (not `DateTime.now()`); duplicate dates (same day + recurring flag) are rejected; holiday changes regenerate schedules for active loans without payments (`holiday_repository.dart`, `loan_repository.dart` `regenSchedulesForActiveLoans`).
- **L5** `Payment.fromMap` tolerates a missing `payment_date`.
- **L6** dead `loans.repayment_day` column dropped via table-recreate (v16 migration); `RepaymentStatus.missed`/`LoanStatus.pending` enum members retained (still used by UI color switches).

Accepted/still-open (documented, not regressions):
- **M14** backup `close()`/reopen of the DB under providers — the close/reopen pattern in `backup_service.dart` is retained as-is.
- **Holiday schedule regen** intentionally skips active loans that already have payments (regenerating would corrupt paid-installment linkage).

Phase 2 (second full-app debug pass, 2026-08-01):
- **C1(2)** FK enforcement moved out of migrations: sqflite runs `onUpgrade` inside a transaction where `PRAGMA foreign_keys` is a no-op, so `_onConfigure` sets `foreign_keys = OFF` and new `_onOpen` sets it `ON`. Without this, the v8/v16 `DROP TABLE loans` table-recreates would cascade into payments/repayment_schedule/documents during upgrade (`database_service.dart`).
- **H1(2)** loan-cleared-with-savings: `clearLoanWithSavings` stamps `prior_loan_status = 'active'` on the payment and inserts the savings withdrawal `AFTER` the payment row with `reference_loan_payment_id` + `type = 'withdrawal'` (was: null status, unlinked, inserted before). `reversePayment` now refunds the linked withdrawal back into the savings account balance and records a `type = 'deposit'` transaction tied to the payment (`payment_repository.dart`).
- **Collection args-order** `getCollectionsByDateRange` had filter placeholders before its 8 date `?` slots — SQLite binds positionally, so filters landed in date params. Args reordered to `[start, end] × 4` then `...filters` (`collection_repository.dart`).
- **Screens route** dead `/customers/:id/payments` removed; real payment history moved to `/loans/:id/payments` (customerId passed via `state.extra` Map); entry button added to `loan_details_screen.dart`.
- **F1(2) export currency** PDF/Excel exports now thread the configured symbol (`currencySymbolProvider`) instead of the hard-coded `₦`: `ExportManager` collection/report/overdue builders take `currencySymbol` (default `CurrencyUtils.defaultSymbol`); callers `collection_screen.dart`, `report_screen.dart`, `overdue_report_screen.dart`, `collection_statement_screen.dart` pass it. Note `_buildReportPdfBytes` uses a local `fmt` closure (lint: no underscore-prefixed locals).
- **F2(2)** dead `companyName` param removed from `ExportManager.shareCollectionExcel`.
- **F3(2)** dead `ExcelExportService.exportFinancialSummaryToXlsx` (+ its `_fmt` and now-unused imports) removed — it was never called.

Full audit details + fix plan: `AUDIT_PLAN.md`.

## Cloud sync (Supabase)

Optional offline-first replication (2026-08-01). The encrypted local SQLite DB stays the source of truth; Supabase mirrors it when the owner signs in (email/password). App unlock remains local-PIN-only.

- **Services:** `lib/core/cloud/` — `supabase_config.dart` (real URL + anon key committed; `isConfigured` is true — never commit the service-role key), `cloud_auth_service.dart`, `cloud_sync_service.dart`, `sync_timestamps.dart`.
- **Config:** `Supabase.initialize` in `main()` (skipped when placeholders present). Auto-sync runs after unlock in `main.dart` (next to `maybeAutoBackup`); manual trigger on the Cloud Sync screen (`/settings/cloud_sync`).
- **Change tracking (v17 migration, `migrations.dart`):** every replicated table gets `updated_at TEXT`; triggers `trg_<table>_{ins,upd,del}` stamp it on normal writes and record deletes in `sync_tombstones`. Bookkeeping tables `sync_flags`, `sync_meta`, `sync_tombstones` are NOT replicated.
- **TIMESTAMP FORMAT (NON-NEGOTIABLE):** all `updated_at` / watermark values MUST use `syncTimestamp()` (`sync_timestamps.dart`) — fixed-width `yyyy-MM-ddTHH:mm:ss.SSSZ` UTC with 3-digit millis. Sync does lexicographic string LWW, so `toIso8601String()` (6-digit micros) or any other format breaks ordering. Same format is produced on the SQLite side by `strftime('%Y-%m-%dT%H:%M:%fZ','now')`.
- **Pull flag:** the sync service sets `sync_flags.pull_in_progress = '1'` while writing pulled rows so the triggers don't re-stamp them or create tombstones. Never write sync tables from app features.
- **LWW merge:** push snapshots changed rows then sets `last_pushed_at` (watermark captured AFTER the snapshot so concurrent writes are re-picked next cycle). Pull deletes parents-first (local FK cascades clean children), then upserts rows where remote `updated_at` > local (or local missing and no newer local tombstone).
- **Documents:** metadata rows replicate like any table (cloud `file_path` is `''`); the encrypted file bytes live in the `documents` storage bucket at `<customer_id>/<document_id>.enc` and are downloaded into `secure_documents/` on pull.
- **Remote schema:** `supabase_schema.sql` must mirror the local schema (column types + FKs). Any local schema change (new table/column) must be added there AND to `_syncTables`/`_tablePrimaryKeys` in `cloud_sync_service.dart` AND the v17/`createSyncSchema` trigger list if it needs change tracking.
- **Tests:** `test/database/migration_v17_sync_test.dart` (real SQLite via `sqflite_common_ffi` — dev dependency) validates the migration, stamping, tombstones, and pull-flag suppression. `supabase_flutter` is a direct dependency; INTERNET permission added to `AndroidManifest.xml`.

## Windows desktop build (packaged with Inno Setup)

First-class desktop port added 2026-08-02. Same encrypted SQLite + PIN/biometric auth as mobile; the DB file lives in the user's Documents folder (`getApplicationDocumentsDirectory()`), key in Windows DPAPI via `flutter_secure_storage`.

- **Encryption on Windows:** `sqflite_sqlcipher` has NO Windows plugin, so `DatabaseService._initDatabase` branches on `Platform.isWindows` and opens via `sqflite_common_ffi` (`databaseFactoryFfi.openDatabase`) using the SQLCipher build of `package:sqlite3`. The key is applied as `PRAGMA key = '<escaped>'` in `onConfigure` (sqflite runs it before the `user_version` check). `verifyDatabaseFile` has the same branch (`_openWindowsDatabaseRaw`). SQLCipher 4 file format — DBs are portable with mobile.
- **Native lib:** the SQLCipher native build is requested in `pubspec.yaml` via `hooks.user_defines.sqlite3.source: sqlcipher` (the `native_toolchain_c` hook system of sqlite3 3.x). `sqlcipher_flutter_libs` (^0.7.0+eol) is a DEAD stub and was REMOVED — do not re-add it. First `flutter build windows` downloads/builds the native lib (needs VS toolchain).
- **Windows runner:** scaffolded by `flutter create --platforms=windows .`; window title + version resources set to "Adeghe Professional Services" in `windows/runner/main.cpp` / `Runner.rc`; launcher icon generated from `attached_assets/app_icon_mark_1024_white_bg.png` into `windows/runner/resources/app_icon.ico` (keep `flutter_launcher_icons.windows` as a Map — `windows: true` is invalid in 0.14.x).
- **Installer:** `windows/installer/setup.iss` (Inno Setup 6). Output `build/installer/AdegheProfessionalServices-Setup-<ver>.exe`, per-user install (`PrivilegesRequired=lowest`), sources from `build/windows/x64/runner/Release`.
- **Prereqs (host, not committed):** Visual Studio 2022 with the "Desktop development with C++" workload, Windows Developer Mode ON (needed for plugin symlinks), and Inno Setup 6 (`ISCC.exe`). Without them `flutter build windows` and the .iss compile both fail.
- **Build steps:** `flutter build windows --release` → open `windows/installer/setup.iss` in Inno Setup Studio and Build (or `ISCC.exe windows\installer\setup.iss` from repo root).
- **No iOS directory:** Only `android/` + `windows/` platform files exist.

## Other notes
- **Backup format:** `.ltbackup` files are ZIP containers (`loantrack.db` + `secure_documents/…`); legacy raw-SQLite files are still accepted on restore (`backup_service.dart`). `archive: ^3.6.1` is a direct dependency.
- **DI inconsistency:** Some repositories take `Ref`, others take `DatabaseService` directly. No uniform pattern.
- **Excel export:** `Excel.rename()` crashes with archive 3.6.1 (unmodifiable list) — never call it; first group reuses `getDefaultSheet()`, later groups use `Sheet_n`. Regression test: `test/excel_encode_test.dart`.
