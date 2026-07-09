-- Optimistic-UI support: a capsule row is now inserted the instant the user
-- taps "Seal", BEFORE the (background) compress/encrypt/upload finishes. So
-- encrypted_payload starts null and a status tracks the upload lifecycle.
alter table public.time_capsules
  alter column encrypted_payload drop not null;

alter table public.time_capsules
  add column if not exists status text not null default 'ready';

alter table public.time_capsules
  add constraint time_capsules_status_check
  check (status in ('pending', 'ready', 'failed'));

-- The creator must be able to fill in encrypted_payload + flip status to
-- 'ready' once the background upload completes. Capsules were previously
-- immutable (no UPDATE policy); this is a deliberate, owner-scoped relaxation.
create policy "time_capsules_update_own"
  on public.time_capsules for update
  using (creator_id = auth.uid())
  with check (creator_id = auth.uid());

-- RPC now also returns status so the recipient's RadarScreen can show a
-- "still materializing" state while a background upload is in flight, vs a
-- normal time-locked countdown. encrypted_payload stays withheld until
-- unlock_time (and is null anyway while pending). Return-type change requires
-- dropping the old signature first.
drop function if exists public.get_capsule_by_share_id(text);

create or replace function public.get_capsule_by_share_id(p_share_id text)
returns table (
  id                uuid,
  share_id          text,
  latitude          float8,
  longitude         float8,
  unlock_time       timestamptz,
  created_at        timestamptz,
  status            text,
  encrypted_payload text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    tc.id,
    tc.share_id,
    tc.latitude,
    tc.longitude,
    tc.unlock_time,
    tc.created_at,
    tc.status,
    case when now() >= tc.unlock_time then tc.encrypted_payload else null end
  from public.time_capsules tc
  where tc.share_id = p_share_id
  limit 1;
$$;

revoke all on function public.get_capsule_by_share_id(text) from public;
revoke all on function public.get_capsule_by_share_id(text) from anon;
grant execute on function public.get_capsule_by_share_id(text) to authenticated;
