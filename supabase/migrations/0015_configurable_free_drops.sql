-- Free-drop allowance is now a configurable COUNT (was a single boolean
-- free_drop_used). The limit lives in system_settings so it can be tuned
-- server-side without a release; per-user usage is tracked as a counter.

-- Per-user counter (backfilled from the old boolean).
alter table public.user_settings
  add column if not exists free_drops_used integer not null default 0;

update public.user_settings
  set free_drops_used = 1
  where free_drop_used = true and free_drops_used = 0;

-- Server-tunable limit (how many free drops each user gets).
insert into public.system_settings (key, value)
  values ('free_drop_limit', 1)
  on conflict (key) do nothing;

-- Atomic increment for the current user, called after a successful drop.
create or replace function public.increment_free_drops_used()
returns void
language sql
security definer
set search_path = public
as $$
  update public.user_settings
    set free_drops_used = free_drops_used + 1
    where user_id = auth.uid();
$$;

revoke all on function public.increment_free_drops_used() from public;
revoke all on function public.increment_free_drops_used() from anon;
grant execute on function public.increment_free_drops_used() to authenticated;
