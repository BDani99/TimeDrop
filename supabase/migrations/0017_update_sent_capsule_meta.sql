-- Creator can update unlock time / pin for a sent capsule; denormalized
-- copies on received_capsules must stay in sync for recipients' Vault UI.
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
begin
  if not exists (
    select 1
    from public.time_capsules tc
    where tc.id = p_capsule_id
      and tc.creator_id = auth.uid()
  ) then
    raise exception 'not authorized';
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

revoke all on function public.update_sent_capsule_meta(uuid, timestamptz, float8, float8, text) from public;
revoke all on function public.update_sent_capsule_meta(uuid, timestamptz, float8, float8, text) from anon;
grant execute on function public.update_sent_capsule_meta(uuid, timestamptz, float8, float8, text) to authenticated;
