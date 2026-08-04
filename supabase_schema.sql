-- ============================================================================
-- Adeghe Professional Services — Supabase cloud-sync schema
-- ============================================================================
-- Run this script in the Supabase dashboard (SQL Editor → New query → Run) for
-- the project used by the app. It mirrors the local SQLite schema so the app's
-- offline-first sync can upsert rows 1:1.
--
-- After running it (SETUP ORDER IS CRITICAL — see API-2):
--   1. FIRST, in Authentication → Providers → Email, turn OFF "Allow new users
--      to sign up". If a stranger can self-register an owner's email before the
--      real account exists, they can claim the owner slot the moment that email
--      is allow-listed (claim_owner grants a slot to any allow-listed email).
--   2. Create BOTH owner accounts at Authentication → Users → Add user, using
--      the owner emails (email + password). The app signs in with those same
--      credentials. Any other account can sign in too, but it is refused a slot
--      (`email_not_authorized` / `is_owner` false) and signed back out, so it
--      can never touch data.
--   3. ONLY AFTER both accounts exist, pre-authorize their emails (dashboard
--      SQL editor — the service role bypasses RLS):
--        insert into authorized_owners (email, note)
--        values ('owner1@example.com', 'Owner 1'), ('owner2@example.com', 'Owner 2');
--      Allow-listing an email before its account exists re-opens the API-2
--      race: an attacker who registered that email while signups were ON would
--      be granted the slot.
--   4. Copy the Project URL and anon key into
--      lib/core/cloud/supabase_config.dart.
--   5. Enable TOTP MFA (Authentication → Auth → MFA) and enroll BOTH owner
--      accounts. A stolen owner password/session can otherwise rewrite or
--      delete the full history, which then propagates to every device via
--      sync_tombstones. There is no in-app MFA enrollment yet — this step is
--      operator-run in the dashboard. To revoke a compromised owner later, call
--      `remove_owner('<auth.uid>')` from the SQL editor (the app never removes
--      itself; a manual RPC is the kill-switch).
--
-- RLS note: every replicated table is locked to the (up to two) owner rows in
-- `app_owner`. The app stamps owners on sign-in via `claim_owner`, which grants
-- a slot ONLY when the caller's auth.email() is on the operator-maintained
-- `authorized_owners` allow-list and derives the id from `auth.uid()` server-
-- side — the caller can never choose who becomes an owner — and serializes
-- concurrent claims with an advisory lock. There is NO role hierarchy: both
-- owners have identical privileges and no other role exists.
-- ============================================================================

-- ── Owner gating ─────────────────────────────────────────────────────────────
-- The operator pre-authorizes the (max two) owner EMAILS in `authorized_owners`
-- from the dashboard SQL editor. SETUP ORDER MATTERS (API-2, 2026-08-04):
--   1. turn OFF "Allow new users to sign up" (Authentication → Providers →
--      Email) FIRST — with signups ON a stranger can self-register an owner's
--      email before the real account exists, then be granted the slot;
--   2. create BOTH owner accounts (Authentication → Users → Add user);
--   3. ONLY THEN allow-list their emails here.
-- `claim_owner` refuses to grant a slot to any account whose auth.email() is
-- not on that allow-list, so "first TWO accounts to sign in win" is abandoned:
-- even with email sign-ups left ON, a stranger cannot create two accounts and
-- capture both owner slots. Every replicated table below is RLS-locked to the
-- auth users listed in `app_owner`. All policies reference `app_owner`, so no
-- other account can read or write any financial data.
--
-- Operator-only bookkeeping: RLS is enabled with NO policy, so neither the
-- public anon key nor any signed-in client can read or mutate it. The operator
-- manages it with the dashboard's SQL editor (the service role bypasses RLS).
-- It is intentionally NOT replicated to devices and NOT exposed via any RPC.
create table if not exists authorized_owners (
  email text primary key,
  note text,
  added_at timestamptz not null default now()
);
alter table authorized_owners enable row level security;

create table if not exists app_owner (
  id text primary key
);
alter table app_owner enable row level security;
create policy "app_owner self" on app_owner
  for select to authenticated using (auth.uid() = id);
grant select on app_owner to authenticated;

-- Hard upper bound of two owners, even if a future code path inserts directly.
create or replace function app_owner_claim_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (select count(*) from app_owner) >= 2 then
    raise exception 'app_owner is full: two owners already exist';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_app_owner_max_two on app_owner;
create trigger trg_app_owner_max_two
  before insert on app_owner
  for each row execute function app_owner_claim_guard();

-- Self-claim with a server-derived owner id, gated on the operator-maintained
-- email allow-list. Returns one of:
--   'ok'                    — slot granted (or this uid already owns one)
--   'email_not_authorized'  — auth.email() is not in `authorized_owners`
--   'full'                  — both owner slots are already taken
-- The advisory lock serializes concurrent claims so the "at most two owners"
-- check cannot be raced (two parallel callers would otherwise both observe
-- count < 2).
--
-- The return type changed from void (first-claim-wins), which `create or
-- replace` cannot change, so the function is dropped and recreated. Grants are
-- re-applied below.
drop function if exists claim_owner();
create or replace function claim_owner()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(auth.email());
begin
  if auth.uid() is null or v_email is null then
    return 'email_not_authorized';
  end if;

  perform pg_advisory_xact_lock(hashtext('loantrack_owner_claim')::bigint);

  if exists (select 1 from app_owner where id = auth.uid()) then
    return 'ok';
  end if;

  if not exists (select 1 from authorized_owners where lower(email) = v_email) then
    return 'email_not_authorized';
  end if;

  if (select count(*) from app_owner) >= 2 then
    return 'full';
  end if;

  insert into app_owner (id) values (auth.uid());
  return 'ok';
end;
$$;

-- Whether the calling authenticated user is one of the project owners. The app
-- refuses to complete sign-in / run sync unless this returns true.
create or replace function is_owner()
returns boolean
language sql
set search_path = public
stable
as $$
  select exists (select 1 from app_owner where id = auth.uid());
$$;

-- The old single-owner signature accepted a caller-supplied owner_id and is a
-- privilege-escalation vector; drop it so stale clients can never call it.
drop function if exists claim_owner(text);
grant execute on function claim_owner() to authenticated;
grant execute on function is_owner() to authenticated;

-- Revocation path for a compromised owner: an existing owner removes the other
-- owner's slot. Refuses to remove the last remaining owner so a compromised
-- account cannot lock the legitimate owner out entirely. Callable only by an
-- owner (SECURITY DEFINER bypasses RLS; the callee check runs as the definer).
-- The operator can also call it from the dashboard SQL editor.
create or replace function remove_owner(target_uid text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_uid is null or length(target_uid) = 0 then
    return 'not_found';
  end if;
  if not exists (select 1 from app_owner where id = auth.uid()) then
    return 'not_owner';
  end if;
  if not exists (select 1 from app_owner where id = target_uid) then
    return 'not_found';
  end if;
  if (select count(*) from app_owner) = 1 then
    return 'last_owner';
  end if;
  delete from app_owner where id = target_uid;
  return 'ok';
end;
$$;
grant execute on function remove_owner(text) to authenticated;

-- ── Business profile ────────────────────────────────────────────────────────
create table if not exists business_profile (
  id text primary key,
  name text not null,
  logo_path text,
  address text,
  phone text,
  email text,
  reg_no text,
  owner_name text,
  updated_at text
);
alter table business_profile enable row level security;
create policy "business_profile all" on business_profile
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Customer groups ─────────────────────────────────────────────────────────
create table if not exists customer_groups (
  id text primary key,
  name text not null,
  description text,
  created_at text not null,
  updated_at text
);
alter table customer_groups enable row level security;
create policy "customer_groups all" on customer_groups
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Customers ───────────────────────────────────────────────────────────────
create table if not exists customers (
  id text primary key,
  passport_path text,
  full_name text not null,
  gender text,
  dob text,
  phone text unique not null,
  alt_phone text,
  email text,
  residential_address text,
  business_address text,
  occupation text,
  employer text,
  marital_status text,
  nationality text,
  state text,
  lga text,
  next_of_kin text,
  next_of_kin_relation text,
  next_of_kin_phone text,
  guarantor_1_name text,
  guarantor_1_phone text,
  guarantor_1_address text,
  guarantor_2_name text,
  guarantor_2_phone text,
  guarantor_2_address text,
  guarantor_passport_path text,
  id_type text,
  id_number text,
  signature_path text,
  date_registered text not null,
  notes text,
  status text not null,
  credit_score double precision default 0.0,
  group_id text references customer_groups(id) on delete set null,
  updated_at text
);
create index if not exists idx_customers_name on customers(full_name);
create index if not exists idx_customers_phone on customers(phone);
create index if not exists idx_customers_group on customers(group_id);
-- Regulated identifiers (BVN/NIN) are NEVER replicated to the cloud: they are
-- stripped from pushed rows in cloud_sync_service.dart (`cloudSensitiveColumns`)
-- and preserved from the local row on pull. Drop the legacy plaintext columns
-- if an earlier script version created them, so the cloud cannot hold them.
alter table customers drop column if exists nin;
alter table customers drop column if exists bvn;
alter table customers enable row level security;
create policy "customers all" on customers
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Loans ───────────────────────────────────────────────────────────────────
create table if not exists loans (
  id text primary key,
  customer_id text not null references customers(id) on delete cascade,
  loan_type text not null,
  amount double precision not null,
  interest_rate double precision not null,
  insurance_fee double precision default 0.0,
  commission double precision default 0.0,
  processing_fee double precision default 0.0,
  admin_fee double precision default 0.0,
  other_charges double precision default 0.0,
  loan_date text not null,
  start_date text not null,
  duration_days integer,
  duration_weeks integer,
  repayment_frequency text,
  daily_payment double precision,
  weekly_payment double precision,
  total_repayment double precision not null,
  outstanding_balance double precision not null,
  expected_completion_date text not null,
  custom_collection_amount double precision,
  collector text,
  notes text,
  status text not null,
  updated_at text
);
create index if not exists idx_loans_customer on loans(customer_id);
create index if not exists idx_loans_type_status on loans(loan_type, status);
create index if not exists idx_loans_type_date on loans(loan_type, loan_date);
alter table loans enable row level security;
create policy "loans all" on loans
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Repayment schedule ──────────────────────────────────────────────────────
create table if not exists repayment_schedule (
  id text primary key,
  loan_id text not null references loans(id) on delete cascade,
  installment_number integer not null,
  due_date text not null,
  amount double precision not null,
  status text not null default 'pending',
  paid_amount double precision not null default 0.0,
  updated_at text
);
create index if not exists idx_repayment_schedule_loan on repayment_schedule(loan_id);
alter table repayment_schedule enable row level security;
create policy "repayment_schedule all" on repayment_schedule
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Payments ────────────────────────────────────────────────────────────────
create table if not exists payments (
  id text primary key,
  loan_id text not null references loans(id) on delete cascade,
  customer_id text not null references customers(id) on delete cascade,
  amount double precision not null,
  payment_date text not null,
  payment_method text not null,
  reference_no text,
  receipt_no text unique not null,
  collector text not null,
  remarks text,
  type text default 'partial',
  status text not null default 'completed',
  prior_loan_status text,
  client_request_id text,
  updated_at text
);
create index if not exists idx_payments_loan on payments(loan_id);
create index if not exists idx_payments_loan_date on payments(loan_id, payment_date);
alter table payments enable row level security;
create policy "payments all" on payments
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Savings accounts ────────────────────────────────────────────────────────
create table if not exists savings_accounts (
  id text primary key,
  customer_id text not null unique references customers(id) on delete cascade,
  balance double precision not null default 0.0,
  created_at text not null,
  updated_at text
);
alter table savings_accounts enable row level security;
create policy "savings_accounts all" on savings_accounts
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Savings transactions ────────────────────────────────────────────────────
create table if not exists savings_transactions (
  id text primary key,
  savings_account_id text not null references savings_accounts(id) on delete cascade,
  type text not null,
  amount double precision not null,
  reference_loan_payment_id text,
  note text,
  created_at text not null,
  updated_at text
);
create index if not exists idx_savings_transactions_account on savings_transactions(savings_account_id);
alter table savings_transactions enable row level security;
create policy "savings_transactions all" on savings_transactions
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Documents (metadata only; encrypted files live in Storage) ──────────────
create table if not exists documents (
  id text primary key,
  customer_id text not null references customers(id) on delete cascade,
  loan_id text references loans(id) on delete cascade,
  doc_type text not null,
  file_path text not null default '',
  original_name text not null,
  mime_type text not null,
  uploaded_at text not null,
  updated_at text
);
create index if not exists idx_documents_customer on documents(customer_id);
alter table documents enable row level security;
create policy "documents all" on documents
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Holidays ────────────────────────────────────────────────────────────────
create table if not exists holidays (
  id text primary key,
  name text not null,
  date text not null,
  is_recurring integer not null,
  is_enabled integer not null,
  updated_at text
);
alter table holidays enable row level security;
create policy "holidays all" on holidays
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Audit logs ──────────────────────────────────────────────────────────────
create table if not exists audit_logs (
  id text primary key,
  "user" text not null,
  action text not null,
  timestamp text not null,
  details text not null,
  updated_at text
);
create index if not exists idx_audit_logs_timestamp on audit_logs(timestamp);
alter table audit_logs enable row level security;
create policy "audit_logs all" on audit_logs
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Settings ────────────────────────────────────────────────────────────────
create table if not exists settings (
  key text primary key,
  value text not null,
  updated_at text
);
alter table settings enable row level security;
create policy "settings all" on settings
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Sync coordination ───────────────────────────────────────────────────────
-- Rows deleted locally are pushed here so other devices can remove them too.
create table if not exists sync_tombstones (
  deleted_table text not null,
  deleted_row_id text not null,
  deleted_at text not null,
  primary key (deleted_table, deleted_row_id)
);
alter table sync_tombstones enable row level security;
create policy "sync_tombstones all" on sync_tombstones
  for all to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- ── Encrypted document files (Storage bucket) ───────────────────────────────
-- Documents are AES-GCM encrypted on-device before upload, so Supabase never
-- sees plaintext. The bucket is private; only authenticated requests can reach
-- the objects, and objects are addressed as <customer_id>/<document_id>.enc.
--
-- The two owners SHARE the bucket: an object is addressed purely by the ids in
-- its key, so an upsert by one owner overwrites the same customer/document id
-- written by the other. That last-write-wins semantics is intentional (mirrors
-- the row LWW merge); a per-owner object namespace would break cross-device
-- doc sync. The server-side guard below still enforces the size and path shape
-- the Dart client already validates (document_repository.dart), so a modified
-- client cannot abuse the bucket for storage-cost attacks or escape the
-- <customer_id>/<document_id>.enc key prefix.
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

-- API-7: `on conflict (id) do nothing` leaves an earlier PUBLIC bucket alone,
-- so re-running this script must harden it back to private. Bucket privacy only
-- affects anonymous access; the owner RLS policy above governs authenticated
-- access either way.
update storage.buckets set public = false where id = 'documents' and public = true;

create policy "documents storage all" on storage.objects
  for all to authenticated
  using (bucket_id = 'documents' and auth.uid() in (select id from app_owner))
  with check (bucket_id = 'documents' and auth.uid() in (select id from app_owner));

-- Server-side size/path enforcement for the documents bucket (defense-in-depth
-- on top of the Dart-side checks). Encrypted files are at most the 20 MB source
-- limit plus ~32 bytes of LTD1 header + GCM IV/tag; 4 KB of margin is allowed.
create or replace function storage.enforce_document_object_rules()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.bucket_id = 'documents' then
    if new.size > 20 * 1024 * 1024 + 4096 then
      raise exception 'documents bucket objects must be 20 MB (encrypted) or smaller';
    end if;
    if new.name !~ '^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+\.enc$' then
      raise exception 'documents bucket objects must use <customer_id>/<document_id>.enc keys';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_document_object_rules on storage.objects;
create trigger trg_document_object_rules
  before insert or update on storage.objects
  for each row execute function storage.enforce_document_object_rules();

-- ── Data integrity checks (API-4, 2026-08-04) ────────────────────────────────
-- The app enforces the same typing at the pull boundary (`isSaneCloudRow` in
-- cloud_sync_service.dart), but the cloud MUST ALSO refuse malformed rows at
-- write time: a tampered owner-session client could otherwise upsert e.g.
-- loans.amount = 'abc' or status = 'x', and the other device's strict entity
-- casts (`(map['amount'] as num)`) would crash. These CHECK constraints mirror
-- the Dart enums and the money rule (amounts are never negative).
--
-- They are added idempotently (helper re-created + dropped each run) so
-- re-running this script upgrades an existing deployment. If one fails, existing
-- rows violate it — fix the offending data first, then re-run. The NOT NULL
-- columns are already declared inline above for fresh installs.
create or replace function add_check_if_not_exists(tbl text, con text, cond text)
returns void
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class r on r.oid = c.conrelid
    join pg_namespace n on n.oid = r.relnamespace
    where n.nspname = 'public' and r.relname = tbl and c.conname = con
  ) then
    execute format('alter table %I add constraint %I check (%s)', tbl, con, cond);
  end if;
end;
$$;

select add_check_if_not_exists('customers', 'ck_customers_status',
  'status in (''active'',''closed'',''blacklisted'',''archived'')');

select add_check_if_not_exists('loans', 'ck_loans_type',
  'loan_type in (''daily'',''weekly'')');
select add_check_if_not_exists('loans', 'ck_loans_status',
  'status in (''active'',''completed'',''defaulted'',''pending'',''cancelled'')');
select add_check_if_not_exists('loans', 'ck_loans_amounts_nonneg',
  'amount >= 0 and total_repayment >= 0 and outstanding_balance >= 0');
select add_check_if_not_exists('loans', 'ck_loans_fees_nonneg',
  'interest_rate >= 0 and insurance_fee >= 0 and commission >= 0 and '
  'processing_fee >= 0 and admin_fee >= 0 and other_charges >= 0 and '
  '(daily_payment is null or daily_payment >= 0) and '
  '(weekly_payment is null or weekly_payment >= 0) and '
  '(custom_collection_amount is null or custom_collection_amount >= 0)');

select add_check_if_not_exists('repayment_schedule', 'ck_repayment_amounts_nonneg',
  'amount >= 0 and paid_amount >= 0');
select add_check_if_not_exists('repayment_schedule', 'ck_repayment_status',
  'status in (''pending'',''paid'',''partial'',''missed'')');

select add_check_if_not_exists('payments', 'ck_payments_amount_nonneg',
  'amount >= 0');
select add_check_if_not_exists('payments', 'ck_payments_status',
  'status in (''completed'',''reversed'')');
select add_check_if_not_exists('payments', 'ck_payments_type',
  'type is null or type in (''partial'',''full'',''advance'',''overpayment'')');

select add_check_if_not_exists('savings_accounts', 'ck_savings_balance_nonneg',
  'balance >= 0');

select add_check_if_not_exists('savings_transactions', 'ck_savings_tx_amount_nonneg',
  'amount >= 0');
select add_check_if_not_exists('savings_transactions', 'ck_savings_tx_type',
  'type in (''deposit'',''withdrawal'',''overpayment'')');

select add_check_if_not_exists('holidays', 'ck_holidays_flags',
  'is_recurring in (0,1) and is_enabled in (0,1)');

drop function if exists add_check_if_not_exists(text, text, text);
