# Adeghe Loan production hardening

Acceptance criteria for the production hardening pass:

1. Database recovery must never delete or replace an existing financial database after SQLCipher/SQLite open failure.
2. Monetary calculations must use exact minor-unit arithmetic at financial boundaries where practical without breaking existing stored data.
3. Schedule rebuilding must avoid N+1 holiday/payment queries for bulk rebuilds.
4. Cloud configuration must not contain committed project-specific credentials; release builds supply configuration explicitly.
5. Financial synchronization must treat payment/savings events as authoritative and balances as projections.
6. Integration tests must cover customer -> loan -> schedule -> partial/full/overpayment -> savings -> withdrawal -> reversal and cross-device synchronization.
7. CI must run analysis, tests, and schema validation.

No production behavior outside these areas should be changed speculatively.
