-- 0031 — once you have paid, your free drop stops being a free drop
--
-- Migration 0024 deletes every capsule funded from the free allowance one
-- month after it opens, sparing only what somebody explicitly kept (a
-- subscriber-only feature). The result is backwards: a person who subscribes
-- but never taps "keep" watches their first memory get deleted on exactly the
-- same schedule as a person who never paid a penny.
--
-- The rule now: anyone who has ever paid — a subscription or a single drop
-- pack — has their free drops treated like every other drop. Permanently,
-- including after they cancel. We do not delete something belonging to
-- somebody who paid us, and we are not going to make that conditional on them
-- still paying.
--
-- WHY A NEW COLUMN
-- ----------------
-- "Has this person ever paid" looks derivable from what we already store, and
-- neither candidate survives contact with reality:
--
--   * `drop_balances.subscription_status` is overwritten wholesale by
--     `merge_drop_balances` from the SOURCE row, so linking an account can
--     turn an 'expired' back into 'none'.
--   * `drop_ledger.user_id` is `on delete cascade`. Buy on an anonymous
--     account, link it, and when the old account is deleted the evidence goes
--     with it.
--
-- So the fact gets its own column, it is only ever set to true, and the merge
-- ORs it instead of overwriting.

alter table public.drop_balances
  add column if not exists has_ever_paid boolean not null default false;

comment on column public.drop_balances.has_ever_paid is
  'True once this user has completed any purchase — subscription or drop pack. '
  'Never reset: not on expiry, not on cancellation, not on refund. Exempts '
  'their free-funded capsules from the retention purge (migration 0024) and '
  'from the free-drop date horizon.';

-- Backfill from whatever evidence still exists for accounts that predate the
-- column. The ledger reasons are the durable ones; subscription_status catches
-- anyone whose ledger rows were pruned.
update public.drop_balances b
   set has_ever_paid = true
 where not b.has_ever_paid
   and (
     b.subscription_status <> 'none'
     or exists (
       select 1 from public.drop_ledger l
        where l.user_id = b.user_id
          and l.reason in ('pack_purchase', 'subscription_cycle')
     )
   );

-- ── rc_apply_event: latch the flag wherever money moved ────────────────────
create or replace function public.rc_apply_event(
  p_event_id text, p_event_type text, p_user uuid, p_product_id text,
  p_purchased_at timestamptz, p_expires_at timestamptz
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_kind text; v_grant int; v_bal public.drop_balances%rowtype;
begin
  if p_user is null then return 'unmapped_user'; end if;

  perform public.ensure_drop_balance(p_user);

  select kind, drops_granted into v_kind, v_grant
    from public.drop_products where product_id = p_product_id and is_active;

  if v_kind is null and p_event_type in (
    'INITIAL_PURCHASE','RENEWAL','UNCANCELLATION','SUBSCRIPTION_EXTENDED',
    'PRODUCT_CHANGE','NON_RENEWING_PURCHASE','CANCELLATION'
  ) then
    return 'unknown_product';
  end if;

  select * into v_bal from public.drop_balances where user_id = p_user for update;

  if v_kind = 'pack' then
    if p_event_type = 'NON_RENEWING_PURCHASE' then
      update public.drop_balances
         set purchased_drops_remaining = purchased_drops_remaining + v_grant,
             has_ever_paid = true, updated_at = now()
       where user_id = p_user;
      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
      values (p_user, v_grant, 'purchased', 'pack_purchase', 'rc:' || p_event_id,
              jsonb_build_object('product_id', p_product_id))
      on conflict (idempotency_key) do nothing;
      return 'applied';
    elsif p_event_type = 'CANCELLATION' then
      -- A refund takes the drops back. It does NOT take back the fact that
      -- they paid — their existing memories stay exempt.
      update public.drop_balances
         set purchased_drops_remaining = greatest(0, purchased_drops_remaining - v_grant), updated_at = now()
       where user_id = p_user;
      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
      select p_user, -least(v_grant, v_bal.purchased_drops_remaining), 'purchased', 'pack_refund',
             'rc:' || p_event_id, jsonb_build_object('product_id', p_product_id)
      on conflict (idempotency_key) do nothing;
      return 'applied';
    end if;
    return 'ignored';
  end if;

  if p_event_type = 'INITIAL_PURCHASE' then
    update public.drop_balances
       set subscription_status = 'active', subscription_product_id = p_product_id,
           subscription_auto_renew = true,
           subscription_period_start = coalesce(p_purchased_at, now()),
           subscription_expires_at = p_expires_at,
           subscription_cycle_start = null,
           subscription_monthly_grant = v_grant,
           has_ever_paid = true, updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type in ('RENEWAL','UNCANCELLATION','SUBSCRIPTION_EXTENDED') then
    update public.drop_balances
       set subscription_status = 'active', subscription_auto_renew = true,
           subscription_expires_at = greatest(
             coalesce(p_expires_at, subscription_expires_at),
             coalesce(subscription_expires_at, p_expires_at)),
           subscription_period_start = coalesce(subscription_period_start, p_purchased_at, now()),
           has_ever_paid = true, updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type = 'PRODUCT_CHANGE' then
    -- Cannot happen without a prior purchase, but setting the flag here costs
    -- nothing and removes the need to reason about that.
    update public.drop_balances
       set subscription_product_id = p_product_id,
           subscription_expires_at = coalesce(p_expires_at, subscription_expires_at),
           subscription_monthly_grant = v_grant,
           has_ever_paid = true, updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type = 'CANCELLATION' then
    update public.drop_balances set subscription_auto_renew = false, updated_at = now()
     where user_id = p_user;
    return 'applied';

  elsif p_event_type = 'BILLING_ISSUE' then
    update public.drop_balances set subscription_status = 'grace', updated_at = now()
     where user_id = p_user;
    return 'applied';

  elsif p_event_type = 'EXPIRATION' then
    if v_bal.subscription_drops_remaining > 0 then
      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key)
      values (p_user, -v_bal.subscription_drops_remaining, 'subscription',
              'subscription_expired', 'rc:' || p_event_id)
      on conflict (idempotency_key) do nothing;
    end if;
    -- has_ever_paid is deliberately untouched: the subscription ended, the
    -- payment still happened.
    update public.drop_balances
       set subscription_status = 'expired', subscription_drops_remaining = 0,
           subscription_auto_renew = false, updated_at = now()
     where user_id = p_user;
    return 'applied';
  end if;

  return 'ignored';
end; $function$;

-- ── merge_drop_balances: OR the flag, never overwrite it ───────────────────
create or replace function public.merge_drop_balances(p_source uuid, p_target uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_src public.drop_balances%rowtype; v_tgt public.drop_balances%rowtype;
  v_limit int; v_before int; v_after int; v_free int; v_purch int; v_key text;
  v_paid boolean;
begin
  if p_source = p_target then return; end if;

  v_key := 'merge:' || p_source || ':' || p_target;
  if exists (select 1 from public.drop_ledger where idempotency_key = v_key) then
    return;
  end if;

  perform public.ensure_drop_balance(p_target);

  select * into v_src from public.drop_balances where user_id = p_source;
  if not found then return; end if;
  select * into v_tgt from public.drop_balances where user_id = p_target for update;

  select coalesce((select value::int from public.system_settings where key = 'free_drop_limit'), 1) into v_limit;

  v_before := v_tgt.free_drops_remaining + v_tgt.subscription_drops_remaining + v_tgt.purchased_drops_remaining;
  v_free  := least(v_tgt.free_drops_remaining + v_src.free_drops_remaining, v_limit);
  v_purch := v_tgt.purchased_drops_remaining + v_src.purchased_drops_remaining;

  -- The subscription block below copies the source's fields wholesale, which
  -- would happily replace a target that HAS paid with a source that has not.
  -- Payment history is the one thing a merge must never lose.
  v_paid := v_tgt.has_ever_paid or v_src.has_ever_paid;

  if coalesce(v_src.subscription_expires_at, '-infinity'::timestamptz)
     > coalesce(v_tgt.subscription_expires_at, '-infinity'::timestamptz) then
    update public.drop_balances
       set free_drops_remaining = v_free, purchased_drops_remaining = v_purch,
           subscription_drops_remaining = v_src.subscription_drops_remaining,
           subscription_status = v_src.subscription_status,
           subscription_product_id = v_src.subscription_product_id,
           subscription_auto_renew = v_src.subscription_auto_renew,
           subscription_period_start = v_src.subscription_period_start,
           subscription_expires_at = v_src.subscription_expires_at,
           subscription_cycle_start = v_src.subscription_cycle_start,
           subscription_monthly_grant = v_src.subscription_monthly_grant,
           has_ever_paid = v_paid,
           updated_at = now()
     where user_id = p_target;
  else
    update public.drop_balances
       set free_drops_remaining = v_free, purchased_drops_remaining = v_purch,
           has_ever_paid = v_paid, updated_at = now()
     where user_id = p_target;
  end if;

  select free_drops_remaining + subscription_drops_remaining + purchased_drops_remaining
    into v_after from public.drop_balances where user_id = p_target;

  insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
  values (p_target, v_after - v_before, 'purchased', 'merge_transfer', v_key,
          jsonb_build_object('source_user_id', p_source::text))
  on conflict (idempotency_key) do nothing;
end; $function$;

-- ── The retention purge skips anyone who has paid ──────────────────────────
create or replace function public.expired_free_capsules(p_limit int default 200)
returns table (capsule_id uuid, creator_id uuid, media_paths text[])
language sql
security definer
set search_path = public
stable
as $$
  select t.id, t.creator_id, t.media_paths
    from public.time_capsules t
   where t.funding_bucket = 'free'
     and t.unlock_time < now() - interval '1 month'
     -- A memory somebody chose to keep outlives the retention rule.
     and not exists (
       select 1 from public.saved_memories s where s.capsule_id = t.id
     )
     -- …and so does everything belonging to somebody who has ever paid.
     and not exists (
       select 1 from public.drop_balances b
        where b.user_id = t.creator_id and b.has_ever_paid
     )
   order by t.unlock_time
   limit p_limit;
$$;

revoke all on function public.expired_free_capsules(int) from public, anon, authenticated;
grant execute on function public.expired_free_capsules(int) to service_role;

-- Re-checks every condition rather than trusting the caller's list, so a stale
-- id from a long-running purge can never take out a capsule that has since
-- been kept — or one whose owner has since paid.
create or replace function public.delete_expired_free_capsules(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  delete from public.time_capsules t
   where t.id = any(p_ids)
     and t.funding_bucket = 'free'
     and t.unlock_time < now() - interval '1 month'
     and not exists (select 1 from public.saved_memories s where s.capsule_id = t.id)
     and not exists (
       select 1 from public.drop_balances b
        where b.user_id = t.creator_id and b.has_ever_paid
     );
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.delete_expired_free_capsules(uuid[]) from public, anon, authenticated;
grant execute on function public.delete_expired_free_capsules(uuid[]) to service_role;

-- ── The free-drop date horizon lifts too ───────────────────────────────────
-- "Behaves like the others" has to include the two-month ceiling. Otherwise a
-- subscriber who still has their free drop unspent gets refused when they aim
-- six months out, with a message about free drops that makes no sense to
-- someone who is paying.
create or replace function public.create_pending_capsule(
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

  if v_bucket = 'free' and not v_bal.has_ever_paid then
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
-- authenticated. CREATE OR REPLACE keeps existing grants, but be explicit.
revoke all on function public.create_pending_capsule(text, double precision, double precision, timestamptz, text) from public, anon;
grant execute on function public.create_pending_capsule(text, double precision, double precision, timestamptz, text) to authenticated;
