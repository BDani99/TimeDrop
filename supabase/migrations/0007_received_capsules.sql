-- Backs the recipient-side "Gallery": every capsule a user has ever
-- resolved as a recipient (via clipboard auto-detect OR manual code/link
-- entry) is tracked here, regardless of unlock status — this is what lets
-- "waiting" (locked, future) and "unlocked" (already viewed) drops persist
-- across app sessions, including for anonymous (unlinked) accounts, since
-- RLS here only cares about auth.uid() matching, not whether that uid
-- belongs to an anonymous or permanent user.
--
-- unlock_time/latitude/longitude are denormalized from time_capsules at
-- insert time (rather than joined) because RLS on time_capsules only
-- allows the CREATOR to select their own rows — a recipient reading via a
-- join would be silently filtered out. The `get_capsule_by_share_id` RPC is
-- the only sanctioned way a recipient reads capsule fields, so its result
-- is what gets copied in here.
--
-- encryption_key is nullable: the key lives only in the share link's hash
-- fragment (see terv.md's Zero-Knowledge design), so a bare 6-character
-- code typed in by hand carries no key. Such rows are tracked (so the user
-- sees "something is coming") but can never be decrypted until the full
-- link is supplied — this is a deliberate consequence of the E2EE design,
-- not a bug.
create table public.received_capsules (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  capsule_id     uuid not null references public.time_capsules(id) on delete cascade,
  share_id       text not null,
  encryption_key text,
  unlock_time    timestamptz not null,
  latitude       float8 not null,
  longitude      float8 not null,
  is_viewed      boolean not null default false,
  first_seen_at  timestamptz not null default now(),
  unique (user_id, capsule_id)
);

create index received_capsules_user_id_idx on public.received_capsules (user_id);

alter table public.received_capsules enable row level security;

create policy "received_capsules_select_own"
  on public.received_capsules for select using (user_id = auth.uid());
create policy "received_capsules_insert_own"
  on public.received_capsules for insert with check (user_id = auth.uid());
create policy "received_capsules_update_own"
  on public.received_capsules for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "received_capsules_delete_own"
  on public.received_capsules for delete using (user_id = auth.uid());
