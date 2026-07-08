create table public.time_capsules (
  id                uuid primary key default gen_random_uuid(),
  creator_id        uuid not null references auth.users(id) on delete cascade,
  share_id          text not null unique,
  encrypted_payload text not null,
  latitude          float8 not null,
  longitude         float8 not null,
  unlock_time       timestamptz not null,
  created_at        timestamptz not null default now(),
  constraint share_id_format check (share_id ~ '^[A-Z0-9]{6}$')
);

create index time_capsules_creator_id_idx on public.time_capsules (creator_id);

alter table public.time_capsules enable row level security;

-- Owner can list/manage their own sent capsules (Sprint 1 "sent" list / My Vault "sent" tab).
create policy "time_capsules_select_own"
  on public.time_capsules for select
  using (creator_id = auth.uid());

create policy "time_capsules_insert_own"
  on public.time_capsules for insert
  with check (creator_id = auth.uid());

-- Capsules are immutable after creation by design; no UPDATE policy.
create policy "time_capsules_delete_own"
  on public.time_capsules for delete
  using (creator_id = auth.uid());

-- IMPORTANT: there is intentionally NO public/broad SELECT policy on this table.
-- Recipient lookup-by-share_id happens exclusively through the SECURITY DEFINER
-- RPC in 0003_get_capsule_by_share_id.sql, never through a direct PostgREST
-- table scan/filter, to prevent any authenticated (trivially-obtained
-- anonymous) user from bulk-enumerating every capsule's lat/long/unlock_time.
