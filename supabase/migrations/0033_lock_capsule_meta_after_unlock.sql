-- 0033 — a sent drop's time, place and sender name freeze once it is
-- discoverable
--
-- update_sent_capsule_meta (migration 0017) has always let the creator move
-- the pin or the clock on ANY of their sent capsules, with no check on
-- whether it had already unlocked. That is harmless while the recipient is
-- still waiting — but the moment unlock_time has passed, the recipient may
-- already be standing in the field with Radar open, walking toward the
-- coordinates this function is about to change out from under them. Their
-- distance reading would jump, or "it only opens where it happened" would
-- quietly stop being true.
--
-- The Flutter client already hides the editing UI once a capsule reaches
-- this state (SentCapsuleDetailScreen._isLocked). This is the server-side
-- half — the real trust boundary, so a modified client cannot reach it
-- either.
--
-- Guards on the row's EXISTING unlock_time, not the incoming p_unlock_time —
-- otherwise a client could dodge the check by proposing a past time in the
-- same call that also moves the pin.
create or replace function public.update_sent_capsule_meta(
  p_capsule_id uuid,
  p_unlock_time timestamptz,
  p_latitude float8,
  p_longitude float8,
  p_city text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_unlock_time timestamptz;
  v_status text;
begin
  select tc.unlock_time, tc.status
    into v_unlock_time, v_status
  from public.time_capsules tc
  where tc.id = p_capsule_id
    and tc.creator_id = auth.uid();

  if not found then
    raise exception 'not authorized';
  end if;

  if v_status = 'ready' and v_unlock_time <= now() then
    raise exception 'this drop is already discoverable and can no longer be edited';
  end if;

  update public.time_capsules
  set
    unlock_time = p_unlock_time,
    latitude = p_latitude,
    longitude = p_longitude,
    city = coalesce(nullif(trim(p_city), ''), city)
  where id = p_capsule_id
    and creator_id = auth.uid();

  update public.received_capsules
  set
    unlock_time = p_unlock_time,
    latitude = p_latitude,
    longitude = p_longitude,
    city = coalesce(nullif(trim(p_city), ''), city)
  where capsule_id = p_capsule_id;
end;
$$;
