-- 0030 — opening a drop with the code alone, when the sender allows it
--
-- The six-character share code has never been enough to open a memory, and
-- that is not an oversight: the decryption key lives in the link's `#`
-- fragment, which browsers never transmit, so the server has genuinely never
-- been able to read anyone's video. A code typed by hand carries no key, so it
-- could only ever put the drop in the recipient's Vault marked "needs the full
-- link".
--
-- That is the right default and it stays the default. But it is a real
-- obstacle when a link gets mangled in a chat app, or when someone wants to
-- read a code out loud. So the SENDER may now decide, per drop, to store the
-- key alongside the capsule and let the bare code open it.
--
-- What that costs, stated plainly: for a capsule with `code_unlock_key` set,
-- this database can decrypt the memory, and so can anyone who obtains both the
-- row and the storage object. End-to-end encryption is off for that one drop.
-- Every other capsule is untouched — the column stays null, and null is what
-- the app sends unless the sender explicitly ticked the box.

alter table public.time_capsules
  add column if not exists code_unlock_key text;

comment on column public.time_capsules.code_unlock_key is
  'AES key (url-safe base64), stored ONLY when the sender chose "openable with '
  'the code too". Its presence means this capsule is deliberately not '
  'end-to-end encrypted: the server can decrypt it. Null on every capsule '
  'where the sender did not opt in, which is the default.';

-- ── create_pending_capsule: accept the opt-in key ──────────────────────────
-- Dropped rather than replaced: adding a parameter changes the function's
-- identity, so CREATE OR REPLACE would leave the old signature behind.
drop function if exists public.create_pending_capsule(text, double precision, double precision, timestamptz);

create function public.create_pending_capsule(
  p_share_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_unlock_time timestamptz,
  p_code_unlock_key text default null
)
returns table(
  capsule_id uuid, bucket text, free_remaining integer,
  subscription_remaining integer, purchased_remaining integer,
  total_remaining integer
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid(); v_capsule uuid; v_reviewer boolean;
  v_bal public.drop_balances%rowtype; v_bucket text; v_horizon int;
begin
  if v_uid is null then raise exception 'Not authenticated' using errcode = 'TD002'; end if;

  select coalesce((select rf.is_reviewer from public.reviewer_flags rf where rf.user_id = v_uid), false) into v_reviewer;

  insert into public.time_capsules
    (creator_id, share_id, latitude, longitude, unlock_time, status, funding_bucket, code_unlock_key)
  values (v_uid, p_share_id, p_latitude, p_longitude, p_unlock_time, 'pending',
          case when v_reviewer then 'reviewer' else null end,
          nullif(p_code_unlock_key, ''))
  returning id into v_capsule;

  if v_reviewer then
    insert into public.drop_ledger (user_id, delta, bucket, reason, capsule_id, metadata)
    values (v_uid, 0, 'reviewer', 'reviewer_bypass', v_capsule, jsonb_build_object('capsule_id', v_capsule::text));
    select * into v_bal from public.drop_balances where user_id = v_uid;
    return query select v_capsule, 'reviewer'::text,
      coalesce(v_bal.free_drops_remaining, 0), coalesce(v_bal.subscription_drops_remaining, 0),
      coalesce(v_bal.purchased_drops_remaining, 0),
      coalesce(v_bal.free_drops_remaining + v_bal.subscription_drops_remaining + v_bal.purchased_drops_remaining, 0);
    return;
  end if;

  perform public.ensure_drop_balance(v_uid);
  select * into v_bal from public.drop_balances where user_id = v_uid for update;
  perform public._apply_subscription_cycle(v_uid);
  select * into v_bal from public.drop_balances where user_id = v_uid;

  v_bucket := case
    when v_bal.free_drops_remaining > 0 then 'free'
    when v_bal.subscription_drops_remaining > 0 then 'subscription'
    when v_bal.purchased_drops_remaining > 0 then 'purchased'
    else null end;

  if v_bucket is null then raise exception 'No drops remaining' using errcode = 'TD001'; end if;

  if v_bucket = 'free' then
    select coalesce((select value::int from public.system_settings where key = 'free_drop_horizon_months'), 2) into v_horizon;
    if p_unlock_time > now() + make_interval(months => v_horizon) then
      raise exception 'Free drops are limited to a % month horizon', v_horizon using errcode = 'TD003';
    end if;
  end if;

  update public.drop_balances
     set free_drops_remaining = free_drops_remaining - (case when v_bucket = 'free' then 1 else 0 end),
         subscription_drops_remaining = subscription_drops_remaining - (case when v_bucket = 'subscription' then 1 else 0 end),
         purchased_drops_remaining = purchased_drops_remaining - (case when v_bucket = 'purchased' then 1 else 0 end),
         updated_at = now()
   where user_id = v_uid;

  update public.time_capsules set funding_bucket = v_bucket where id = v_capsule;

  insert into public.drop_ledger (user_id, delta, bucket, reason, capsule_id, idempotency_key, metadata)
  values (v_uid, -1, v_bucket, 'capsule_reserve', v_capsule, 'reserve:' || v_capsule,
          jsonb_build_object('capsule_id', v_capsule::text));

  select * into v_bal from public.drop_balances where user_id = v_uid;
  return query select v_capsule, v_bucket,
    v_bal.free_drops_remaining, v_bal.subscription_drops_remaining, v_bal.purchased_drops_remaining,
    v_bal.free_drops_remaining + v_bal.subscription_drops_remaining + v_bal.purchased_drops_remaining;
end; $function$;

-- `from public` alone is not enough: Supabase's default privileges grant
-- EXECUTE on every newly created function in this schema directly to anon and
-- authenticated, so a recreated function silently gains an anon grant it never
-- had. Revoke from anon by name.
revoke all on function public.create_pending_capsule(text, double precision, double precision, timestamptz, text) from public, anon;
grant execute on function public.create_pending_capsule(text, double precision, double precision, timestamptz, text) to authenticated;

-- ── get_capsule_by_share_id: hand back the key only when it exists ─────────
-- Gated exactly like the payload: nothing is released before the unlock time,
-- so an opted-in capsule is no more readable early than any other one.
drop function if exists public.get_capsule_by_share_id(text);

create function public.get_capsule_by_share_id(p_share_id text)
returns table(
  id uuid, share_id text, latitude double precision, longitude double precision,
  unlock_time timestamptz, created_at timestamptz, status text,
  encrypted_payload text, code_unlock_key text
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid(); v_limit int; v_misses int; v_found boolean;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  select coalesce((select s.value::int from public.system_settings s
                    where s.key = 'share_lookup_miss_hourly_limit'), 20)
    into v_limit;

  -- Only MISSES are counted. The radar polls this same endpoint every three
  -- seconds while a drop is still uploading, so a limit on all calls would
  -- break the app for the people using it correctly.
  select count(*) into v_misses from public.share_lookup_misses m
   where m.user_id = v_uid and m.attempted_at > now() - interval '1 hour';

  if v_misses >= v_limit then
    raise exception 'Too many failed lookups. Try again later.' using errcode = 'TD005';
  end if;

  select exists(select 1 from public.time_capsules tc where tc.share_id = p_share_id)
    into v_found;

  if not v_found then
    insert into public.share_lookup_misses (user_id, share_id) values (v_uid, p_share_id);
    delete from public.share_lookup_misses
     where user_id = v_uid and attempted_at < now() - interval '24 hours';
  end if;

  return query
    select tc.id, tc.share_id, tc.latitude, tc.longitude, tc.unlock_time,
           tc.created_at, tc.status,
           case when now() >= tc.unlock_time then tc.encrypted_payload else null end,
           case when now() >= tc.unlock_time then tc.code_unlock_key else null end
      from public.time_capsules tc
     where tc.share_id = p_share_id
     limit 1;
end; $function$;

revoke all on function public.get_capsule_by_share_id(text) from public, anon;
grant execute on function public.get_capsule_by_share_id(text) to authenticated;
