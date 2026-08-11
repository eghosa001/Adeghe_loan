# AUDIT_REPORTS.md — Reports module audit + redesign (2026-08-11)

Scope: the Reports dashboard (`lib/features/reports/`) and its sub-report
screens, audited for **data correctness**, **performance**, **consistency**
and **security**, then redesigned into a dashboard-style layout. The app's
main dashboard (`lib/features/dashboard/`) was **not** touched.

## What changed (this pass)

| File | Change |
| --- | --- |
| `lib/features/reports/data/report_repository.dart` | New `getReportDashboard()` (line 101): ONE batched call computes the period summary, the previous-period summary (for deltas), today's collections + top collectors, overdue risk (total + 1-7/8-14/15+ day buckets + top accounts), savings (balance/in/out) and customer stats. |
| `lib/features/reports/data/models/report_models.dart` | New dashboard aggregate types: `CollectorTotal`, `TodayCollection`, `OverdueBucket`, `OverdueAccount`, `OverdueRisk`, `SavingsSummary`, `CustomerStats`, `ReportDashboardData`. |
| `lib/features/reports/presentation/providers/report_provider.dart` | New `reportDashboardProvider` (family keyed on `ReportDateRange`). |
| `lib/features/reports/presentation/screens/report_screen.dart` | Full dashboard redesign (see below). |
| `test/reports/report_dashboard_test.dart` | NEW — 4 money-rule/aggregation regression tests for `getReportDashboard`. |

The redesigned dashboard sections:
1. **Reporting period selector** (existing preset chips + custom range) with a
   **compact loan-type filter** merged directly underneath so both filters
   read as one control block (`_LoanTypeFilter`).
2. **Six primary KPI cards** — Total Collected, Total Disbursed, Net Profit,
   Outstanding, Expected, Collection Efficiency — each with a **delta vs the
   previous equal-length period** (`_PrimaryKpis`, `_KpiCard`).
3. **Today's Collection** — collected today (money rule), payment count, due
   today (unpaid portion, holidays excluded), collection progress, top
   collectors, link to the Collection screen.
4. **Loan Portfolio** — active loans, period disbursed, outstanding, loans due
   today, defaulted, completed.
5. **Collection Performance** — efficiency donut (`_EfficiencyDonut`),
   Collected vs Expected caption, Collected vs Disbursed trend bars.
6. **Overdue & Risk** — overdue amount, overdue loans, age buckets as
   severity bars, top overdue accounts, link to the Overdue report.
7. **Income & Profit** — net profit, interest, fees, profit split by loan
   type, link to the Profit report.
8. **Savings** — total balance, in/out/net flow for the period, savings
   in-vs-out line chart, link to the Savings report.
9. **Customers** — total (non-archived), new in period, customers with active
   loans, new-customer + new-loan trend bars, link to the Customer report.
10. **Report Screens** nav grid (six sub-reports) at the bottom.

### Sub-report screen consistency

Already consistent — verified, no changes needed. All six sub-report screens
(`daily_loan_report_screen.dart`, `weekly_loan_report_screen.dart`,
`overdue_report_screen.dart`, `customer_report_screen.dart`,
`savings_report_screen.dart`, `profit_report_screen.dart`) are built from the
same shared kit in `lib/features/reports/presentation/widgets/report_ui.dart`:
`ReportScreenShell`, `ReportPeriodSelector`, `ReportMetricStrip`,
`ReportDataTable`, `ReportExportBar`. Exports flow through the one
`ReportExportData` pipeline in `services/export_manager.dart` and the shared
`runReportExport` helper. A new sub-report can only be "inconsistent" by
deviating from these widgets.

## Data correctness

Verified against the NON-NEGOTIABLE money rule (AGENTS.md): every aggregate
over payments filters `p.status = 'completed'` AND subtracts the savings
overpayment surplus via
`LEFT JOIN savings_transactions st ON st.reference_loan_payment_id = p.id AND st.type = 'overpayment'`.

| Query | Location | Rule status |
| --- | --- | --- |
| Collected in period | `report_repository.dart:405` (also `:144`, `:155`, `:926`) | `SUM(p.amount - COALESCE(st.amount, 0.0))`, `p.status = 'completed'` — compliant |
| Client report `totalPaid` / `savingsAmount` | `report_repository.dart:501-510` | money rule + separate savings ledger — compliant |
| Customer report `totalCollected` | `report_repository.dart:693` | subquery money rule — compliant |
| Profit report `totalCollected` | `report_repository.dart:823` | subquery money rule — compliant |
| Dashboard today-collected + top collectors | `report_repository.dart:144`, `:155` | money rule, `payment_date = today` — compliant |
| Savings inflow (period) | `report_repository.dart:160-165` | `deposit` OR `overpayment` linked to a **completed** payment — matches the trends savings-in rule |
| Overdue figures | `report_repository.dart:168-215` | unpaid portion `rs.amount - COALESCE(rs.paid_amount, 0)` on unpaid installments `DATE(due_date) < today`, `l.status IN ('active','defaulted')`, holidays excluded |

Specific correctness points confirmed:
- **Reversed payments never aggregate.** The `p.status = 'completed'` filter
  applies everywhere, including the new today/top-collector queries.
- **Savings overpayments never inflate collected totals** (owner decision,
  2026-08-01): the `- COALESCE(st.amount, 0.0)` subtraction is present in
  every collected figure including today's.
- **Distinct customer counts.** Summary `totalCustomers` uses
  `COUNT(DISTINCT l.customer_id)` (`:50-55`); the new `CustomerStats`
  distinguishes *all* non-archived customers from customers *with active
  loans*, so the two product-intent counts are never conflated.
- **Cancelled loans never disburse or earn.** Disbursed/interest/fees queries
  filter `l.status IN ('active','completed','defaulted')` (`:196-207`); the
  dashboard reuses those sums.
- **Overdue is only past-due, never future-due.** Boundary is `DATE(due_date) < today`
  with Dart-local `today` (never `date('now')`, which is UTC) — `:106`, `:365`,
  and the new bucket queries.
- **Holiday safety net.** The new dashboard's due-today and overdue queries
  reuse `notOnEnabledHolidaySql` (`lib/core/database/holiday_sql.dart`), so a
  holiday never shows as collectable or overdue even if schedules predate it.
- **Date-only bounds on ISO timestamps.** Savings queries use
  `substr(st.created_at, 1, 10) BETWEEN start AND end` — never a `'... 23:59:59'`
  space-form bound (AGENTS.md dates rule).
- **Previous-period deltas are equal-length.** The previous window is the same
  number of days immediately before the period start
  (`report_repository.dart:116-118`), so "Today → Yesterday", "This Month →
  Last Month", and "Last 30 Days → the 30 days before" are all apples-to-apples.
  `getReportSummary` computes it, so it is money-rule-identical to the current
  period.

## Performance

- **Single snapshot.** The dashboard now renders from ONE `getReportDashboard`
  call (13 scalar queries in one `Future.wait` + the two summaries in a
  parallel `Future.wait`). Previously the 18 cards came from the summary alone;
  the new sections would have added 6+ extra serial round trips per render had
  they queried independently.
- **Batched queries everywhere.** `_getLoanTypeSummary` runs 12 scalars in one
  batch (`:385-430`) and its heavy detail queries in a second batch (`:483-500`),
  gated by `includeDetail` (`:354`, `:37`) so the combined dashboard never pays
  for the client-report/overdue detail lists.
- **Trends already batched.** `getDashboardTrends` builds all bucket queries
  up front and runs a single `Future.wait` (`:870-980`) — 186 sequential round
  trips → one batch (fix documented in AGENTS.md audit 2026-08-07).
- **Result caching.** `reportDashboardProvider` and `dashboardTrendsProvider`
  are `FutureProvider.family` keyed on `ReportDateRange`; changing the period
  or loan type rebuilds only the affected key, and the refresh action
  invalidates only the current key.
- **Index coverage** (`database_service.dart:550-577`): `idx_savings_txns_ref_payment`
  backs the money-rule join; `idx_payments_date`, `idx_payments_loan_date`,
  `idx_savings_txns_created`, `idx_loans_type_status`, `idx_loans_type_date`,
  `idx_repayment_schedule_loan_date` back the date-range and status filters.

Known cost: `getReportDashboard` computes the previous-period summary, which
doubles summary work per dashboard render. Accepted — it is one extra batched
summary, cached per range, and the payoff is that every primary-card delta is
computed from the same code path as the card itself.

## Consistency

- **One number, one query.** The dashboard's six primary cards read the same
  `ReportSummary` fields the old 18-card grid and the sub-report headers read.
  Today/overdue/savings/customers are new queries but are defined once and
  shared by every widget in the section they feed — no widget re-derives a
  figure in Dart.
- **Export fidelity.** `ReportExportData` rows are pre-formatted display
  strings (`export_manager.dart:29-33`), so a PDF/Excel export can never
  produce a number different from the screen's data. The dashboard export
  builds from the same summary + trends objects the UI renders.
- **Loan-type filter flows UI → provider → repository** in both the dashboard
  (`reportLoanTypeFilterProvider`) and the sub-reports; the excluded loan-type
  bucket is returned `empty()` so combined totals never halve
  (`report_summary.dart:22-37`, `report_summary.dart:87-94`).
- **Savings scope note (intentional):** savings aggregates are *not*
  loan-type-scoped (a savings account belongs to a customer, not a loan type).
  The `loanType` filter is ignored for savings inflow/outflow/balance — the
  same behaviour as the existing `savingsIn/savingsOut` trend series.
- **Deliverable definition locked:** the "Collected vs Expected" comparison is
  rendered as the efficiency donut + a Collected/Expected caption, not a
  per-bucket bar, because per-bucket *expected* would require duplicating the
  installment-due aggregation in a second shape — a divergence risk for no
  dashboard value.

## Security

- All report data is read from the encrypted local SQLCipher DB through the
  locked `DatabaseService`; no report code touches secrets or network.
- Money-rule enforcement is defence-in-depth: even a malformed payment row can
  never inflate a collected total (overpayments and reversed rows are excluded
  in SQL, not in the UI).
- No string interpolation of untrusted input into SQL: every parameter is a
  bound `?` argument, and `ltClause` is a compile-time constant fragment.
- Holiday exclusion SQL is a shared `const` fragment, not re-inlined per query.
- Date handling follows the app-wide rule (Dart-local dates; never UTC
  `date('now')`), so a device clock is the only clock the reports trust.

## Open items (accepted, not regressions)

1. **Overdue "top accounts"** groups by loan, not by customer. A customer with
   several overdue loans appears more than once in the top-5 list. Grouping by
   customer would require a new query shape; left as-is to stay consistent with
   the Overdue report's per-installment view.
2. **Previous-period summary cost** (see Performance) — accepted for cached
   dashboard renders.
3. The dashboard's overdue figures are computed at render time; the Overdue
   sub-report is likewise computed at its own render time. Both share the same
   query semantics, so they only differ if data changes between renders (a
   live-data property, not a drift bug).

## Verification

```bash
flutter analyze --no-pub   # clean
flutter test               # 244 passing (240 prior + 4 new dashboard tests)
```

New regression tests (`test/reports/report_dashboard_test.dart`):
- today collection follows the money rule (overpayments subtracted, reversed
  payments excluded, top collectors match);
- overdue buckets by age (1-7 / 8-14 / 15+) and totals, future-due excluded;
- savings balance/in/out and customer totals/new/active counts, archived
  customers excluded everywhere;
- previous-period summary feeds the primary-card deltas.
