-- Cloud-sync v2: server-authoritative monotonic versions and safe tombstone deletes.
-- Apply this migration to the Supabase project used by Adeghe_loan.
create sequence if not exists public.cloud_sync_version_seq;

alter table public.sync_tombstones add column if not exists sync_version bigint not null default 0;

alter table public.business_profile add column if not exists sync_version bigint not null default 0;
alter table public.customer_groups add column if not exists sync_version bigint not null default 0;
alter table public.customers add column if not exists sync_version bigint not null default 0;
alter table public.loans add column if not exists sync_version bigint not null default 0;
alter table public.payments add column if not exists sync_version bigint not null default 0;
alter table public.savings_accounts add column if not exists sync_version bigint not null default 0;
alter table public.savings_transactions add column if not exists sync_version bigint not null default 0;
alter table public.documents add column if not exists sync_version bigint not null default 0;
alter table public.holidays add column if not exists sync_version bigint not null default 0;

create index if not exists idx_business_profile_sync_version on public.business_profile(sync_version);
create index if not exists idx_customer_groups_sync_version on public.customer_groups(sync_version);
create index if not exists idx_customers_sync_version on public.customers(sync_version);
create index if not exists idx_loans_sync_version on public.loans(sync_version);
create index if not exists idx_payments_sync_version on public.payments(sync_version);
create index if not exists idx_savings_accounts_sync_version on public.savings_accounts(sync_version);
create index if not exists idx_savings_transactions_sync_version on public.savings_transactions(sync_version);
create index if not exists idx_documents_sync_version on public.documents(sync_version);
create index if not exists idx_holidays_sync_version on public.holidays(sync_version);
create index if not exists idx_sync_tombstones_sync_version on public.sync_tombstones(sync_version);

select setval(
  'public.cloud_sync_version_seq',
  greatest(
    0,
    coalesce((select max(sync_version) from public.business_profile),0),
    coalesce((select max(sync_version) from public.customer_groups),0),
    coalesce((select max(sync_version) from public.customers),0),
    coalesce((select max(sync_version) from public.loans),0),
    coalesce((select max(sync_version) from public.payments),0),
    coalesce((select max(sync_version) from public.savings_accounts),0),
    coalesce((select max(sync_version) from public.savings_transactions),0),
    coalesce((select max(sync_version) from public.documents),0),
    coalesce((select max(sync_version) from public.holidays),0),
    coalesce((select max(sync_version) from public.sync_tombstones),0)
  ), true
);

-- Assign authoritative versions to legacy rows that still have 0.
update public.business_profile set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.customer_groups set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.customers set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.loans set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.payments set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.savings_accounts set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.savings_transactions set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.documents set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;
update public.holidays set sync_version = nextval('public.cloud_sync_version_seq') where sync_version = 0;

create or replace function public.assign_cloud_sync_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.sync_version := nextval('public.cloud_sync_version_seq');
    return new;
  end if;

  -- A stale offline device carries an older version. Returning OLD from a
  -- BEFORE trigger cancels the update, preventing stale data from winning.
  if new.sync_version < old.sync_version then
    return old;
  end if;

  -- Equal/current versions are treated as an edit based on the current
  -- server snapshot; the server assigns the next global version.
  new.sync_version := nextval('public.cloud_sync_version_seq');
  return new;
end;
$$;

-- Idempotent trigger creation for repeated deployments.
drop trigger if exists trg_cloud_sync_version on public.business_profile;
create trigger trg_cloud_sync_version before insert or update on public.business_profile for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.customer_groups;
create trigger trg_cloud_sync_version before insert or update on public.customer_groups for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.customers;
create trigger trg_cloud_sync_version before insert or update on public.customers for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.loans;
create trigger trg_cloud_sync_version before insert or update on public.loans for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.payments;
create trigger trg_cloud_sync_version before insert or update on public.payments for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.savings_accounts;
create trigger trg_cloud_sync_version before insert or update on public.savings_accounts for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.savings_transactions;
create trigger trg_cloud_sync_version before insert or update on public.savings_transactions for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.documents;
create trigger trg_cloud_sync_version before insert or update on public.documents for each row execute function public.assign_cloud_sync_version();
drop trigger if exists trg_cloud_sync_version on public.holidays;
create trigger trg_cloud_sync_version before insert or update on public.holidays for each row execute function public.assign_cloud_sync_version();

create or replace function public.apply_sync_tombstone(p_table text, p_row_id text, p_base_version bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_version bigint;
  row_exists boolean;
  new_version bigint;
  existing_tombstone_version bigint;
begin
  if (select auth.uid()) is null or not exists (select 1 from public.app_owner where id = (select auth.uid())) then
    raise exception 'not_owner';
  end if;

  if p_table is null or p_row_id is null or length(p_row_id) = 0 or length(p_row_id) > 128
     or p_table <> all(array['business_profile','customer_groups','customers','loans','payments','savings_accounts','savings_transactions','documents','holidays']) then
    raise exception 'invalid_tombstone_target';
  end if;

  -- Serialize against a concurrent update/delete of the target row.
  execute format('select sync_version from public.%I where id = $1 for update', p_table)
    into current_version using p_row_id;
  row_exists := found;

  if row_exists and current_version > coalesce(p_base_version,0) then
    return jsonb_build_object('applied', false, 'reason', 'stale', 'sync_version', current_version);
  end if;

  -- An already-recorded newer tombstone wins over an older duplicate request.
  select sync_version into existing_tombstone_version
  from public.sync_tombstones
  where deleted_table = p_table and deleted_row_id = p_row_id
  for update;
  if existing_tombstone_version is not null and existing_tombstone_version > coalesce(p_base_version,0) then
    return jsonb_build_object('applied', false, 'reason', 'stale_tombstone', 'sync_version', existing_tombstone_version);
  end if;

  if row_exists then
    execute format('delete from public.%I where id = $1', p_table) using p_row_id;
  end if;

  new_version := nextval('public.cloud_sync_version_seq');
  insert into public.sync_tombstones(deleted_table, deleted_row_id, deleted_at, sync_version)
    values (p_table, p_row_id, to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), new_version)
  on conflict (deleted_table, deleted_row_id) do update
    set deleted_at = excluded.deleted_at, sync_version = excluded.sync_version;

  return jsonb_build_object('applied', true, 'sync_version', new_version);
end;
$$;

revoke all on function public.apply_sync_tombstone(text,text,bigint) from public;
revoke all on function public.apply_sync_tombstone(text,text,bigint) from anon;
grant execute on function public.apply_sync_tombstone(text,text,bigint) to authenticated;
