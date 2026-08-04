-- ============================================================================
-- Adeghe Professional Services — Supabase cloud-sync schema
-- ============================================================================
-- Run this script in the Supabase dashboard (SQL Editor → New query → Run) for
-- the project used by the app. It mirrors the local SQLite schema so the app's
-- offline-first sync can upsert rows 1:1.
--
-- After running it:
--   1. Create the owner account(s): Authentication → Users → Add user
--      (email + password). The app signs in with those same credentials. The
--      first TWO distinct accounts to sign in on any device become the project
--      owners (see `claim_owner`). Any other account can sign in too, but the
--      app refuses to sync for it (`is_owner`), so it can never touch data.
--   2. Copy the Project URL and anon key into
--      lib/core/cloud/supabase_config.dart.
--   3. In Authentication → Providers → Email, turn OFF "Allow new users to
--      sign up". The anon key is public (it ships in the app), so anyone could
--      otherwise create an account and race to claim an owner slot.
--
-- RLS note: every table is locked to the (up to two) owner rows in `app_owner`.
-- The app stamps owners on sign-in via `claim_owner`, which derives the id from
-- `auth.uid()` server-side — the caller can never choose who becomes an owner —
-- and serializes concurrent claims with an advisory lock. There is NO role
-- hierarchy: both owners have identical privileges and no other role exists.
-- ============================================================================

-- ── Owner gating ─────────────────────────────────────────────────────────────
-- Two-owner app: every replicated table below is RLS-locked to the auth users
-- listed in `app_owner`. After an owner signs in for the first time, the app
-- calls `claim_owner` (SECURITY DEFINER), which inserts the caller's own
-- auth.uid() — never a client-supplied value — only while the table holds fewer
-- than two rows. All policies reference `app_owner`, so no other account can
-- read or write any financial data.
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

-- Self-claim with a server-derived owner id. The advisory lock serializes
-- concurrent first claims so the "at most two owners" check cannot be raced
-- (two parallel callers would otherwise both observe count < 2).
create or replace function claim_owner()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(hashtext('loantrack_owner_claim')::bigint);
  insert into app_owner (id)
  select auth.uid()
  where auth.uid() is not null
    and not exists (select 1 from app_owner where id = auth.uid())
    and (select count(*) from app_owner) < 2;
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
  nin text unique,
  bvn text unique,
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
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

create policy "documents storage all" on storage.objects
  for all to authenticated
  using (bucket_id = 'documents' and auth.uid() in (select id from app_owner))
  with check (bucket_id = 'documents' and auth.uid() in (select id from app_owner));
