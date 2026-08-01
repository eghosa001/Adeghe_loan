# Audit Plan — Full-Application Debug & Recurrence Prevention

Date: 2026-07-31. Baseline: `flutter analyze` clean, `flutter test` 29/29 passing.
Source: 4 parallel audits (loans/payments/DB, reports/dashboard/collection/savings, auth/security/router/backup, business/customers/groups/UI/export), every finding re-verified against source.
Duplicate findings from multiple audits are merged here.

**Totals: 5 Critical, 14 High, 22 Medium, 6 Low (+ stale AGENTS.md claims).**

---

## PART A — CONSOLIDATED FINDINGS

### CRITICAL (crash / data loss / security)

| # | Bug | Location | Why it fails | Fix |
|---|-----|----------|--------------|-----|
| C1 | Loan list crashes on every row — `NoSuchMethodError` | `lib/features/loans/presentation/screens/loan_list_screen.dart:187-189` | `(loan as dynamic).customerName` — `Loan` entity has no such getter and `Loan.fromMap` drops the `customer_name` the SQL selects (`loan_repository.dart:115`). Every tile render throws; the Loans screen is unusable. | Add a real `customerName` field on `Loan`, populated from `map['customer_name']`. |
| C2 | Analytics growth stats permanently error — `no such column: created_at` | `lib/features/reports/data/report_repository.dart:399, 415` | `customers` table defines `date_registered` (never `created_at`). Both queries throw `DatabaseException`, caught and surfaced as a permanent error section. | Replace `created_at` → `date_registered`; fix end-of-month bound (see M5). |
| C3 | Auto-lock never locks the screen | `lib/main.dart:21-24`, `lib/core/router/app_router.dart` | `onInactivity` only calls `authProvider.lock()`. No router `redirect`, no listener, no `WidgetsBindingObserver`. After 5 min the current screen stays visible and DB providers hang on the locked `Completer().future` — frozen UI until force-kill. | Watch `authProvider` in a router `redirect` (locked → `/auth/pin`) and navigate immediately on inactivity + lifecycle `paused`. |
| C4 | Restore deletes live DB before validating backup — silent total data loss | `lib/features/backup/data/backup_service.dart:60-80` | Deletes current DB file before copying; no header/version check, no rollback, no try/catch. A corrupt backup → `finally` reopens and `onCreate` makes a brand-new empty DB. | Copy to temp → open/verify with DB key → atomic swap; delete old only after verification. |
| C5 | No PIN attempt limit — unlimited brute force | `lib/features/auth/presentation/screens/pin_login_screen.dart:61-87` | No attempt counter/lockout in login path. `keyFailedAttempts`/`keyLockoutUntil` never referenced. 4-digit space trivially brute-forced. | Persist attempts + lockout expiry in secure storage; shared helper reused by login/change/forgot. |

### HIGH (wrong money data / stored-but-ignored settings)

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| H1 | "Pay in full"/multi-installment payments dump surplus to savings | `lib/features/payments/data/payment_logic.dart:43-44`, `payment_repository.dart:207-217`; root cause `_getNextInstallmentAmount` `payment_repository.dart:27-36` | Cap loan split at `outstandingBalance` (sum of remaining installments), not a single raw installment; use remaining owed (`amount - paid_amount`) per installment. UI `_surplus` already uses outstanding balance — align backend. |
| H2 | Custom collection amount → schedule sum ≠ `total_repayment`/`outstanding_balance` | `lib/features/loans/presentation/providers/loan_providers.dart:167-201` | Store `total_repayment = effectiveInstallment × duration` and matching outstanding when custom amount set. |
| H3 | Editing a loan never regenerates schedule/totals; `customCollectionAmount` edit ignored | `loan_providers.dart:220-235`, `loan_repository.dart:72-80` | On edit, recompute derived fields + rewrite `repayment_schedule` in a transaction; pass `customCollectionAmount` to `copyWith`. |
| H4 | Loans list silently capped at 50 | `loan_repository.dart:96` (`limit: 50` default), consumed with no pagination | Paginate (offset on scroll) or remove limit for list screen. |
| H5 | Collection range totals: `amountDue` = one installment vs `amountPaid` = all payments; reversed + overpayment portions counted | `lib/features/collection/data/collection_repository.dart:107-145` | `amountDue` = `SUM(rs.amount - rs.paid_amount)` for unpaid in-range installments; add `p.status='completed'` and subtract savings overpayments (`p.amount - COALESCE(st.amount,0.0)`). |
| H6 | Client report `totalPaid` includes savings overpayment portions | `lib/features/reports/data/report_repository.dart:212` | Same overpayment LEFT JOIN + subtraction pattern. |
| H7 | End-of-month rows silently dropped — ISO `T` vs space separator | `report_repository.dart:159-166` (`savingsFromOverpayments`), `:447-453` (`getSavingsTrends`), also affects C2 chart | Compare on date only: `DATE(created_at) >= ? AND DATE(created_at) <= ?` or `created_at < DATE(?,'+1 day')`. |
| H8 | Cancelled loans counted in Disbursed / Interest / Fees / Expected Collections | `report_repository.dart:114-117, 138-157` | Add `AND l.status IN ('active','completed','defaulted')` to disbursed/interest/fees; `status='active'` to expected collections. Dashboard already filters — screens disagree. |
| H9 | Session-timeout setting saved but never applied | `settings_screen.dart:34-43` writes; `main.dart:21` uses default | Load saved minutes before building `InactivityWrapper`; pass `timeout:`. |
| H10 | PIN / recovery password stored as unsalted single SHA-256 | `lib/core/security/secure_storage_service.dart:22-30, 67-69`; `keyPinSalt` unused | Per-pin random salt + PBKDF2 (HMAC iterations). |
| H11 | `/documents/preview` unguarded `state.extra as CustomerDocument` | `lib/core/router/app_router.dart:201-204` | Null-safe cast + error/empty state (or load by id). |
| H12 | Forgot-PIN lockout is widget-local memory only; recovery password free-form | `lib/features/auth/presentation/screens/forgot_pin_screen.dart:21-22, 66-78` | Persist attempts + lockout; enforce minimum password strength at setup. |
| H13 | PIN-setup permanently stuck if recovery dialog cancelled | `lib/features/auth/presentation/screens/pin_setup_screen.dart:46-93` | On dialog dismiss reset `_pin`/`_confirm`/`_isConfirming`. |
| H14 | Auto-backup toggle is decorative | `settings_screen.dart:163-169` | Consume `auto_backup_enabled` (on-start/unlock check vs `pref_last_backup_date` → prompt). |

### MEDIUM

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| M1 | Reversal corrupts loan status (completed→active with 0 balance; defaulted→active on partial) | `payment_repository.dart:302-308, 218` | Preserve prior status; derive from schedule not balance. |
| M2 | Report loan-type filter is a no-op | `report_provider.dart:64`, `report_repository.dart:32-35` | Thread the filter into the summary query or drop the param. |
| M3 | `savingsFromOverpayments` counts reversed payments' overpayments | `report_repository.dart:159-167` | Add `AND p.status='completed'`. |
| M4 | Savings trends ignore `'overpayment'` transaction type | `report_repository.dart:449-451` | Include `type='overpayment'` in deposits CASE. |
| M5 | Overdue semantics: summary counts future-in-period dues; Overdue tab misses pre-period overdue | `report_repository.dart:104-111, 242` | Drive Overdue tab from `getOverdueReport()`; summary overdue count uses `due_date < today`. |
| M6 | Dashboard Today/7-day mix local dates with UTC `date('now')` | `dashboard_repository.dart:50, 57` | Pass Dart local today string; `BETWEEN` with explicit end bound. |
| M7 | Legacy `loan_type='monthly'` rows invisible in daily/weekly aggregates | `migrations.dart` (v8) | Rewrite `'monthly'` → `'weekly'` in migration. |
| M8 | Dashboard "Recent Payments" includes reversed | `dashboard_repository.dart:61` | Add `status='completed'`. |
| M9 | Report "Total Customers" double counts (daily + weekly) | `report_screen.dart:329` | `COUNT(DISTINCT customer_id)` across types. |
| M10 | Configured currency symbol ignored everywhere; `₦` hard-coded | `currency_utils.dart:18-28`; hard-coded in `record_payment_screen.dart:188`, `notification_provider.dart:36,61,92`, `global_search_repository.dart:91`, `collection_screen.dart:384` | Expose `currencySymbolProvider`; thread through all `format()` calls. |
| M11 | `decryptFile` leaks raw `FileSystemException`, hides real error | `file_encryption_service.dart:38-56` | Wrap read too; rethrow `FileEncryptionException` chaining cause. |
| M12 | Backup excludes encrypted documents — restore breaks every document | `backup_service.dart:23-39` | Include `secure_documents/`; remap paths on restore. |
| M13 | `notificationProvider` recomputes every unlock; SQL unguarded; read state never persisted | `notification_provider.dart:8-118` | Guard queries, cache, persist `read`. |
| M14 | DB double-open + backup closes DB under active providers | `database_service.dart:17-21`, `backup_service.dart:24` | Memoize init future; pause/queue DB access during backup. |
| M15 | Change-PIN has no attempt limit / error handling | `change_pin_screen.dart:46-52` | Reuse shared lockout helper (from C5). |
| M16 | Biometric enable doesn't verify identity; unhandled exceptions | `security_settings_screen.dart:31-43`, `pin_login_screen.dart:48-54` | Require successful `authenticate()`; wrap storage calls. |
| M17 | `InactivityWrapper` only resets on tap/pan — misses scroll/typing | `inactivity_wrapper.dart:44-47` | Also reset on focus/keyboard / global pointer listener. |
| M18 | Loan form state is global and never reset — wrong terms saved silently | `loan_providers.dart:255-258`, `loan_creation_screen.dart:24-48, 178, 217` | Reset `loanFormProvider` on screen entry; bind fields to notifier via `initialValue`. |
| M19 | DB failures rethrown as exceptions in `saveLoan`/`updateLoan` — unhandled crash | `loan_providers.dart:216, 250` | Surface failure via state/snackbar, don't `throw`. |
| M20 | "Share statement" button actually prints | `loan_statement_screen.dart:95-99` | Use `SharePlus.instance.share` on generated PDF. |
| M21 | On-screen loan statement excludes non-active loans; PDF includes all | `loan_statement_screen.dart:108` | Use `allLoansForCustomerProvider`. |
| M22 | Deleting a customer silently wipes all financial history (ON DELETE CASCADE) | `customer_repository.dart:189-216`, `database_service.dart:147,165-166,179,193-194,231,244` | Block deletion when active loans / non-zero savings exist, or confirm with counts. |

### LOW / CLEANUP

| # | Bug | Location | Fix |
|---|-----|----------|-----|
| L1 | Same-day exports overwrite each other | `export_manager.dart:195-199,346-349,358-362,859-863,935-939`, `excel_export_service.dart:40-44`, `savings_overview_screen.dart:51-57`, `group_management_screen.dart:256+` | Append timestamp/uuid to filename. |
| L2 | Group "Undo" re-creates empty group, members lost | `group_management_screen.dart:241-251` | Restore members' `group_id` or recreate with original id. |
| L3 | Holiday date parse fallback silently corrupts dates | `holiday_entity.dart:48` (`?? DateTime.now()`) | Fail closed / log + skip. |
| L4 | No duplicate-holiday guard; edits don't regenerate schedules | `holiday_repository.dart` | Validate uniqueness; regenerate schedules on holiday change. |
| L5 | `Payment.fromMap` forced null cast | `payment_entity.dart:78` | Fall back to `DateTime.now()`. |
| L6 | Dead schema: `loans.repayment_day` never written; `RepaymentStatus.missed`/`LoanStatus.pending` unused | `database_service.dart:137`, entities | Remove or document. |

### STALE AGENTS.md CLAIMS (verified fixed — refresh the doc)

- `getScheduleForLoan` wrong-table bug: **fixed** (`loan_repository.dart:164-168`).
- Currency symbol mismatch `$` vs `₦`: **fixed** — both default `₦`; real issue is M10.
- `pinLength` unused: **fixed** — used in setup/login/change.
- `defaultInactivityTimeout` mismatch: **fixed** — 5 min both sides; real issue is H9.
- `flex_color_scheme` / `flutter_local_notifications` unused: **removed** from pubspec.
- Orphaned `loan_entity.dart`, `flutter_01.log`: **removed**.

---

## PART B — FIX PLAN (phased, dependency-ordered)

### Phase 0 — Critical (do first, each independently shippable)
1. **C1** Add `customerName` to `Loan` (`fromMap` + UI). *Test: widget test rendering a loan tile.*
2. **C2** `created_at` → `date_registered` (2 spots) + date-only bounds (H7) so the chart works too.
3. **C3** Router `redirect` on `authProvider` + `WidgetsBindingObserver` pause-lock.
4. **C4** Temp-file restore with key verification + atomic swap + rollback.
5. **C5** Shared `PinLockoutService` (persisted attempts/lockout) used by login, forgot, change-PIN.

### Phase 1 — High (money correctness + settings wiring)
1. **H1** Fix payment split cap to outstanding balance; `_getNextInstallmentAmount` returns remaining owed. *Test: split unit tests incl. "Pay in full" and partial-first-installment cases.*
2. **H3/H2** Single `recomputeSchedule(loan)` helper used by create, edit, and custom-amount path; regenerate `repayment_schedule` in a transaction on edit.
3. **H5** Collection range `amountDue` = unpaid in-range sums; filter `status='completed'`; subtract overpayments. *Test: integration query test with reversed + overpayment fixtures.*
4. **H6** Client `totalPaid` overpayment subtraction.
5. **H8** Status filters on disbursed/interest/fees/expected.
6. **H4** Paginate loan list.
7. **H9** Read saved session-timeout in `main()`.
8. **H10** Salted PBKDF2 hashing for PIN/recovery (keep old hash readable for one login, then re-hash).
9. **H11** Null-safe `state.extra` + guard.
10. **H12/H13** Persist forgot-PIN lockout; strength check; reset setup state on dialog dismiss.
11. **H14** Wire auto-backup toggle to a real on-start prompt/check.

### Phase 2 — Medium (correctness + robustness)
M1 reversal status, M2 loan-type filter, M3 reversed overpayment exclusion, M4 overpayment in savings trends, M5 overdue semantics, M6 local-day windows, M7 monthly→weekly migration, M8 recent-payments filter, M9 distinct customers, M10 currency symbol provider, M11 decrypt error wrapping, M12 documents in backup, M13 notification provider guard/cache, M14 DB init memoize + backup pause, M15/M16/M17 auth hardening, M18 form reset + initialValue, M19 no-throw providers, M20 share-not-print, M21 statement consistency, M22 delete-with-history confirmation.

### Phase 3 — Low + hygiene
L1–L6, plus AGENTS.md refresh (see Prevention §6).

---

## PART C — RECURRENCE PREVENTION (this is the deliverable's core ask)

The bugs above cluster into **5 root causes**. Kill the root cause and the class cannot re-occur:

### 1. SQL name-drift (C2, H5, H6, H7, M6, M8, and the historical `repayment_installments` bug)
**Fix: schema-authority test.** Add `test/database/schema_crosscheck_test.dart` that opens the real schema (from `database_service`), reads every table/column name, then **parses every `rawQuery`/`query` string in `lib/features/*/data/*.dart`** and asserts each referenced table/column exists. A typo becomes a compile-time test failure, not a runtime crash. Run on every PR.

### 2. Money-aggregation drift (H1, H5, H6, M3, M4, M8, and the 4 fixes already shipped)
**Fix: one canonical money rule + one helper.** Define in a single place (e.g. `lib/core/database/money_sql.dart`):
- `kSavingsOverpaymentJoin` (LEFT JOIN `savings_transactions` on `reference_loan_payment_id`, `type='overpayment'`)
- `kCompletedPaymentFilter` (`p.status = 'completed'`)
- `paidMinusOverpaymentSql` = `(p.amount - COALESCE(st.amount, 0.0))`

Every `SUM(p.amount)` must be written as `paidMinusOverpaymentSql` + `kCompletedPaymentFilter`. **Add a CI grep/lint check** (script) that fails if any `SUM(p.amount` appears without the overpayment subtraction. Document the rule in AGENTS.md.

### 3. Dynamic-access / unsafe casts (C1, H11)
**Fix: tighten analysis.** Add to `analysis_options.yaml`:
- `avoid_dynamic_calls` (would have caught C1 at analyze-time)
- keep `use_build_context_synchronously`, `discarded_futures`, `unawaited_futures`

Run `flutter analyze` in CI; treat warnings as errors (`flutter analyze --fatal-infos`).

### 4. State/settings stored but never consumed (H9, H14, M10, M13, C3, C5)
**Fix: settings-authority pattern.** Every persisted setting must have exactly one consumer provider and one test asserting it is read. Add `test/settings_consumed_test.dart` that greps each `AppConstants.key*/pref*` constant for a read-site outside its write-screen. C3/C5 get their own shared services so the lock/navigation/attempt logic exists in exactly one place and cannot silently drift.

### 5. Unsafe destructive I/O (C4, M12, M14)
**Fix: write-path discipline.** All file/DB destructive operations go through helpers that do *temp-write → verify → atomic rename* and are wrapped to never delete live data before the replacement verifies. Backup includes documents. Add integration tests for backup/restore round-trip.

### 6. Docs must stay true
Refresh `AGENTS.md`: move the 7 fixed claims into a "Changelog / verified-fixed" section, add a live "Known open bugs" table (the tables above), and record the money rule and SQL rule so future sessions can't reintroduce them. Keep `AUDIT_PLAN.md` as the living bug log; strike items as they ship.

### 7. CI gate (no CI exists today)
Add `.github/workflows/ci.yml`: on push/PR → `flutter pub get` + `flutter analyze --fatal-infos` + `flutter test` + the schema-crosscheck + money-rule grep. This is the single strongest guarantee that "stop recurrence" holds after this session.

---

## Suggested execution order
Phase 0 (C1→C5) → Phase 1 (H1→H14) → prevention items §1–§3 (schema test, money helper, lint) alongside → Phase 2 → Phase 3 → CI (§7) + AGENTS.md refresh (§6).

Each Phase-0/1 fix lands with its own regression test (widget/unit/integration), so the suite grows from 29 → ~60+ tests and backstops every bug class.
