-- Adeghe Professional Services — sync tombstone retention
--
-- SECURITY/REPLICATION FIX:
-- Remote tombstones must be durable. The previous `for all` policy allowed a
-- client to DELETE a tombstone after consuming it. If another device was
-- offline at that moment, it could miss the deletion and later re-upload the
-- stale row, resurrecting deleted financial/customer data.
--
-- We deliberately allow SELECT/INSERT/UPDATE for owners but do NOT grant a
-- DELETE policy. With Supabase/PostgREST RLS, a client DELETE therefore affects
-- zero rows without removing the tombstone. The existing client treats this as
-- idempotent success, while the tombstone remains available to every other
-- device (and to the same device on subsequent syncs).
--
-- IMPORTANT: Run this migration in the Supabase SQL Editor for the live project.
-- Committing this file does not alter an already-deployed Supabase schema.

begin;

alter table sync_tombstones enable row level security;

drop policy if exists "sync_tombstones all" on sync_tombstones;
drop policy if exists "sync_tombstones select" on sync_tombstones;
drop policy if exists "sync_tombstones insert" on sync_tombstones;
drop policy if exists "sync_tombstones update" on sync_tombstones;
drop policy if exists "sync_tombstones delete" on sync_tombstones;

create policy "sync_tombstones select" on sync_tombstones
  for select to authenticated
  using (auth.uid() in (select id from app_owner));

create policy "sync_tombstones insert" on sync_tombstones
  for insert to authenticated
  with check (auth.uid() in (select id from app_owner));

create policy "sync_tombstones update" on sync_tombstones
  for update to authenticated
  using (auth.uid() in (select id from app_owner))
  with check (auth.uid() in (select id from app_owner));

-- Intentionally NO DELETE policy.
-- Tombstones are append-only from the clients' perspective.

commit;
