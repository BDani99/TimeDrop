-- The drop ledger: the server-owned source of truth for how many drops a user
-- may create, replacing the client-side `free_drops_used` gate.
--
-- WHY THIS REPLACES THE OLD GATE
-- ------------------------------
-- Previously the client inserted the capsule row and separately called
-- `increment_free_drops_used()`, best-effort, swallowing failures. Two calls,
-- neither authoritative: a drop could be created without being paid for, or
-- paid for without being created. With money attached to the quota that is no
-- longer acceptable. `create_pending_capsule()` below does both in ONE
-- transaction, so they cannot disagree.
--
-- THREE BUCKETS
-- -------------
--   free          one-time grant at signup, never refilled
--   subscription  OVERWRITTEN to the monthly grant at each cycle boundary
--   purchased     consumable packs; permanent, additive
--
-- Debit order is free -> subscription -> purchased. Subscription drops are
-- use-it-or-lose-it while purchased ones never expire, so purchased must be
-- spent last or a subscriber would silently burn drops they paid extra for.
--
-- WHY A LAZY CYCLE ROLLOVER INSTEAD OF "RESET ON THE RENEWAL WEBHOOK"
-- ------------------------------------------------------------------
-- An ANNUAL subscriber emits one RENEWAL per year but must still receive 10
-- drops every month. `subscription_period_start` is a fixed anchor set once at
-- purchase; every read derives how many whole months have elapsed and resets
-- the bucket when the cycle advances. Monthly and annual therefore share one
-- code path, it is idempotent, needs no cron, and survives a late or dropped
-- webhook.

-- ── Tunables ─────────────────────────────────────────────────────────────────
-- NOTE: `free_drop_limit` is deliberately NOT touched here. It is currently
-- raised well above 1 for development, and it lives in system_settings exactly
-- so the shipping value is an operator decision, not a code change. Set it to 1
-- before release:  update public.system_settings set value = 1
--                   where key = 'free_drop_limit';
insert into public.system_settings (key, value) values
  ('subscription_monthly_grant', 10),
  ('subscription_grace_days',     2),
  ('free_drop_horizon_months',    2)
on conflict (key) do nothing;

-- ── Reviewer flag ────────────────────────────────────────────────────────────
-- Lives here rather than in 0021 because `create_pending_capsule` must consult
-- it; 0021 adds the passcode machinery that sets it. A reviewer bypasses the
-- quota SERVER-SIDE, so store review works even though enforcement is real.
create table public.reviewer_flags (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  is_reviewer boolean not null default false,
  granted_at  timestamptz,
  revoked_at  timestamptz
);

alter table public.reviewer_flags enable row level security;

create policy "reviewer_flags_select_own"
  on public.reviewer_flags for select
  using (user_id = auth.uid());

-- No write policies: only the SECURITY DEFINER passcode RPC (0021) may grant.
revoke insert, update, delete on table public.reviewer_flags from anon, authenticated;

-- ── Balances ─────────────────────────────────────────────────────────────────
create table public.drop_balances (
  user_id                      uuid primary key references auth.users(id) on delete cascade,
  free_drops_remaining         integer     not null default 0,
  subscription_drops_remaining integer     not null default 0,
  purchased_drops_remaining    integer     not null default 0,

  subscription_status          text        not null default 'none'
    check (subscription_status in ('none', 'active', 'grace', 'expired')),
  subscription_product_id      text,
  subscription_auto_renew      boolean     not null default true,
  -- ANCHOR: set once at INITIAL_PURCHASE, never moved. Moving it would hand a
  -- monthly subscriber an extra reset on every renewal.
  subscription_period_start    timestamptz,
  subscription_expires_at      timestamptz,
  -- Start of the monthly cycle whose grant has already been issued.
  subscription_cycle_start     timestamptz,
  subscription_monthly_grant   integer     not null default 10,

  updated_at                   timestamptz not null default now(),

  constraint drop_balances_non_negative check (
    free_drops_remaining >= 0
    and subscription_drops_remaining >= 0
    and purchased_drops_remaining >= 0
  )
);

alter table public.drop_balances enable row level security;

create policy "drop_balances_select_own"
  on public.drop_balances for select
  using (user_id = auth.uid());

-- Writes go exclusively through the SECURITY DEFINER functions below.
revoke insert, update, delete on table public.drop_balances from anon, authenticated;

-- ── Ledger ───────────────────────────────────────────────────────────────────
-- Append-only. `sum(delta)` per user must always equal the sum of that user's
-- three balances (excluding bucket='reviewer', whose deltas are always 0).
create table public.drop_ledger (
  id              bigserial primary key,
  user_id         uuid    not null references auth.users(id) on delete cascade,
  delta           integer not null,
  bucket          text    not null check (bucket in ('free', 'subscription', 'purchased', 'reviewer')),
  reason          text    not null,
  capsule_id      uuid    references public.time_capsules(id) on delete set null,
  idempotency_key text,
  -- Keeps the capsule id as text after the FK above is nulled on delete, so
  -- the audit trail survives the capsule it describes.
  metadata        jsonb   not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

-- Deliberately NOT a partial index. Postgres treats NULLs as distinct in a
-- unique index, so this already permits unlimited key-less rows (reviewer
-- bypasses) while enforcing uniqueness of real keys — and, unlike a partial
-- index, `ON CONFLICT (idempotency_key)` can infer it without repeating a
-- predicate at every call site.
create unique index drop_ledger_idem_idx
  on public.drop_ledger (idempotency_key);

create index drop_ledger_user_idx on public.drop_ledger (user_id, created_at desc);

alter table public.drop_ledger enable row level security;

create policy "drop_ledger_select_own"
  on public.drop_ledger for select
  using (user_id = auth.uid());

revoke insert, update, delete on table public.drop_ledger from anon, authenticated;

-- ── Which bucket funded each capsule ─────────────────────────────────────────
-- Denormalised from the ledger so the retention job (0023) and the UI can tell
-- a free drop from a paid one without a join. Existing rows stay NULL, which
-- the retention rule treats as "not a free drop" — deliberately conservative.
alter table public.time_capsules
  add column if not exists funding_bucket text
  check (funding_bucket in ('free', 'subscription', 'purchased', 'reviewer'));

-- ── Provisioning ─────────────────────────────────────────────────────────────
create or replace function public.ensure_drop_balance(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_free  int;
  v_grant int;
begin
  select coalesce((select value::int from public.system_settings where key = 'free_drop_limit'), 1)
    into v_free;
  select coalesce((select value::int from public.system_settings where key = 'subscription_monthly_grant'), 10)
    into v_grant;

  insert into public.drop_balances (user_id, free_drops_remaining, subscription_monthly_grant)
  values (p_user, v_free, v_grant)
  on conflict (user_id) do nothing;

  -- Only mint the opening ledger entry when this call actually created the
  -- balance. Writing it unconditionally would re-credit the ledger — without
  -- touching the balance — for any user whose opening row had gone missing,
  -- silently breaking the `sum(delta) = balance` invariant. The idempotency
  -- key is a second line of defence, not the primary one.
  if found then
    insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key)
    values (p_user, v_free, 'free', 'signup_free', 'signup_free:' || p_user)
    on conflict (idempotency_key) do nothing;
  end if;
end;
$$;

revoke all on function public.ensure_drop_balance(uuid) from public, anon, authenticated;

-- Client-callable, self-scoped wrapper: a safety net for accounts created
-- before this migration, called once during app bootstrap.
create or replace function public.ensure_own_drop_balance()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;
  perform public.ensure_drop_balance(auth.uid());
end;
$$;

revoke all on function public.ensure_own_drop_balance() from public, anon;
grant execute on function public.ensure_own_drop_balance() to authenticated;

-- Extend the existing provisioning trigger rather than adding a second one.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;

  perform public.ensure_drop_balance(new.id);
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- ── Subscription cycle rollover ──────────────────────────────────────────────
-- Internal: assumes the caller already holds the row lock.
create or replace function public._apply_subscription_cycle(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bal    public.drop_balances%rowtype;
  v_grace  int;
  v_months int;
  v_cycle  timestamptz;
begin
  select * into v_bal from public.drop_balances where user_id = p_user;
  if not found or v_bal.subscription_period_start is null then
    return;
  end if;

  select coalesce((select value::int from public.system_settings where key = 'subscription_grace_days'), 2)
    into v_grace;

  if v_bal.subscription_status in ('active', 'grace')
     and v_bal.subscription_expires_at is not null
     and now() < v_bal.subscription_expires_at + make_interval(days => v_grace)
  then
    v_months := extract(year  from age(now(), v_bal.subscription_period_start)) * 12
              + extract(month from age(now(), v_bal.subscription_period_start));
    v_cycle  := v_bal.subscription_period_start + make_interval(months => v_months);

    if v_bal.subscription_cycle_start is null or v_cycle > v_bal.subscription_cycle_start then
      -- OVERWRITE, not add: unused drops from last month do not carry over.
      update public.drop_balances
         set subscription_drops_remaining = v_bal.subscription_monthly_grant,
             subscription_cycle_start     = v_cycle,
             updated_at                   = now()
       where user_id = p_user;

      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
      values (
        p_user,
        v_bal.subscription_monthly_grant - v_bal.subscription_drops_remaining,
        'subscription',
        'subscription_cycle',
        'cycle:' || p_user || ':' || to_char(v_cycle, 'YYYY-MM-DD'),
        jsonb_build_object('cycle_start', v_cycle)
      )
      on conflict (idempotency_key) do nothing;
    end if;

  elsif v_bal.subscription_status <> 'expired' or v_bal.subscription_drops_remaining > 0 then
    -- Lapsed: the monthly bucket empties. Free and purchased are untouched.
    if v_bal.subscription_drops_remaining > 0 then
      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key)
      values (
        p_user,
        -v_bal.subscription_drops_remaining,
        'subscription',
        'subscription_expired',
        'expire:' || p_user || ':' || coalesce(to_char(v_bal.subscription_expires_at, 'YYYYMMDDHH24MISS'), 'null')
      )
      on conflict (idempotency_key) do nothing;
    end if;

    update public.drop_balances
       set subscription_drops_remaining = 0,
           subscription_status          = 'expired',
           updated_at                   = now()
     where user_id = p_user;
  end if;
end;
$$;

revoke all on function public._apply_subscription_cycle(uuid) from public, anon, authenticated;

-- ── Read model ───────────────────────────────────────────────────────────────
create or replace function public.get_drop_state()
returns table (
  free_remaining          integer,
  subscription_remaining  integer,
  purchased_remaining     integer,
  total_remaining         integer,
  next_bucket             text,
  max_unlock_time         timestamptz,
  is_reviewer             boolean,
  subscription_status     text,
  subscription_expires_at timestamptz,
  next_cycle_reset_at     timestamptz,
  can_create              boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_bal      public.drop_balances%rowtype;
  v_reviewer boolean;
  v_horizon  int;
  v_next     text;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  perform public.ensure_drop_balance(v_uid);
  perform public._apply_subscription_cycle(v_uid);

  select * into v_bal from public.drop_balances where user_id = v_uid;
  select coalesce((select rf.is_reviewer from public.reviewer_flags rf where rf.user_id = v_uid), false)
    into v_reviewer;
  select coalesce((select value::int from public.system_settings where key = 'free_drop_horizon_months'), 2)
    into v_horizon;

  v_next := case
    when v_bal.free_drops_remaining         > 0 then 'free'
    when v_bal.subscription_drops_remaining > 0 then 'subscription'
    when v_bal.purchased_drops_remaining    > 0 then 'purchased'
    else null
  end;

  return query select
    v_bal.free_drops_remaining,
    v_bal.subscription_drops_remaining,
    v_bal.purchased_drops_remaining,
    v_bal.free_drops_remaining + v_bal.subscription_drops_remaining + v_bal.purchased_drops_remaining,
    case when v_reviewer then 'reviewer' else v_next end,
    -- Only a free drop is horizon-capped; paid drops may target any future date.
    case when not v_reviewer and v_next = 'free'
         then now() + make_interval(months => v_horizon)
         else null end,
    v_reviewer,
    v_bal.subscription_status,
    v_bal.subscription_expires_at,
    case when v_bal.subscription_cycle_start is not null
         then v_bal.subscription_cycle_start + interval '1 month'
         else null end,
    v_reviewer
      or (v_bal.free_drops_remaining + v_bal.subscription_drops_remaining
          + v_bal.purchased_drops_remaining) > 0;
end;
$$;

revoke all on function public.get_drop_state() from public, anon;
grant execute on function public.get_drop_state() to authenticated;

-- ── The single atomic write path ─────────────────────────────────────────────
-- Inserts the capsule AND debits a drop in one transaction. A share_id
-- collision (23505) propagates unchanged so the client's existing retry loop
-- still works, and rolls the debit back with it.
create or replace function public.create_pending_capsule(
  p_share_id    text,
  p_latitude    double precision,
  p_longitude   double precision,
  p_unlock_time timestamptz
)
returns table (
  capsule_id             uuid,
  bucket                 text,
  free_remaining         integer,
  subscription_remaining integer,
  purchased_remaining    integer,
  total_remaining        integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_capsule  uuid;
  v_reviewer boolean;
  v_bal      public.drop_balances%rowtype;
  v_bucket   text;
  v_horizon  int;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  select coalesce((select rf.is_reviewer from public.reviewer_flags rf where rf.user_id = v_uid), false)
    into v_reviewer;

  -- creator_id is taken from the JWT, never from a parameter: this function is
  -- SECURITY DEFINER and therefore bypasses the RLS check that would otherwise
  -- stop a client from creating capsules owned by someone else.
  insert into public.time_capsules
    (creator_id, share_id, latitude, longitude, unlock_time, status, funding_bucket)
  values
    (v_uid, p_share_id, p_latitude, p_longitude, p_unlock_time, 'pending',
     case when v_reviewer then 'reviewer' else null end)
  returning id into v_capsule;

  if v_reviewer then
    insert into public.drop_ledger (user_id, delta, bucket, reason, capsule_id, metadata)
    values (v_uid, 0, 'reviewer', 'reviewer_bypass', v_capsule,
            jsonb_build_object('capsule_id', v_capsule::text));

    select * into v_bal from public.drop_balances where user_id = v_uid;
    return query select
      v_capsule, 'reviewer'::text,
      coalesce(v_bal.free_drops_remaining, 0),
      coalesce(v_bal.subscription_drops_remaining, 0),
      coalesce(v_bal.purchased_drops_remaining, 0),
      coalesce(v_bal.free_drops_remaining + v_bal.subscription_drops_remaining
               + v_bal.purchased_drops_remaining, 0);
    return;
  end if;

  perform public.ensure_drop_balance(v_uid);

  -- FOR UPDATE serialises a double-tapped "Seal": the second call waits, then
  -- sees the already-decremented balance.
  select * into v_bal from public.drop_balances where user_id = v_uid for update;
  perform public._apply_subscription_cycle(v_uid);
  select * into v_bal from public.drop_balances where user_id = v_uid;

  v_bucket := case
    when v_bal.free_drops_remaining         > 0 then 'free'
    when v_bal.subscription_drops_remaining > 0 then 'subscription'
    when v_bal.purchased_drops_remaining    > 0 then 'purchased'
    else null
  end;

  if v_bucket is null then
    raise exception 'No drops remaining' using errcode = 'TD001';
  end if;

  if v_bucket = 'free' then
    select coalesce((select value::int from public.system_settings where key = 'free_drop_horizon_months'), 2)
      into v_horizon;
    if p_unlock_time > now() + make_interval(months => v_horizon) then
      raise exception 'Free drops are limited to a % month horizon', v_horizon
        using errcode = 'TD003';
    end if;
  end if;

  update public.drop_balances
     set free_drops_remaining         = free_drops_remaining         - (case when v_bucket = 'free'         then 1 else 0 end),
         subscription_drops_remaining = subscription_drops_remaining - (case when v_bucket = 'subscription' then 1 else 0 end),
         purchased_drops_remaining    = purchased_drops_remaining    - (case when v_bucket = 'purchased'    then 1 else 0 end),
         updated_at = now()
   where user_id = v_uid;

  update public.time_capsules set funding_bucket = v_bucket where id = v_capsule;

  insert into public.drop_ledger (user_id, delta, bucket, reason, capsule_id, idempotency_key, metadata)
  values (v_uid, -1, v_bucket, 'capsule_reserve', v_capsule,
          'reserve:' || v_capsule, jsonb_build_object('capsule_id', v_capsule::text));

  select * into v_bal from public.drop_balances where user_id = v_uid;
  return query select
    v_capsule, v_bucket,
    v_bal.free_drops_remaining,
    v_bal.subscription_drops_remaining,
    v_bal.purchased_drops_remaining,
    v_bal.free_drops_remaining + v_bal.subscription_drops_remaining + v_bal.purchased_drops_remaining;
end;
$$;

revoke all on function public.create_pending_capsule(text, double precision, double precision, timestamptz)
  from public, anon;
grant execute on function public.create_pending_capsule(text, double precision, double precision, timestamptz)
  to authenticated;

-- ── Discard + refund ─────────────────────────────────────────────────────────
-- Deletes a capsule the caller owns and, when it never reached 'ready',
-- returns its drop. A delivered capsule is a spent drop and is not refunded.
create or replace function public.discard_capsule(p_capsule_id uuid)
returns table (
  refunded               boolean,
  bucket                 text,
  free_remaining         integer,
  subscription_remaining integer,
  purchased_remaining    integer,
  total_remaining        integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_status    text;
  v_bucket    text;
  v_bal       public.drop_balances%rowtype;
  v_refunded  boolean := false;
  v_target    text;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = 'TD002';
  end if;

  perform public.ensure_drop_balance(v_uid);
  -- Lock the balance row first, in the same order create_pending_capsule takes
  -- it, so a concurrent create and discard cannot deadlock.
  perform 1 from public.drop_balances where user_id = v_uid for update;

  select status, funding_bucket into v_status, v_bucket
    from public.time_capsules
   where id = p_capsule_id and creator_id = v_uid
   for update;

  if not found then
    raise exception 'Capsule not found' using errcode = 'TD004';
  end if;

  -- Refund only an undelivered capsule funded from a real bucket, and only if
  -- this capsule has not already been refunded.
  if v_status is distinct from 'ready'
     and v_bucket in ('free', 'subscription', 'purchased')
     and exists (select 1 from public.drop_ledger
                  where idempotency_key = 'reserve:' || p_capsule_id)
     and not exists (select 1 from public.drop_ledger
                      where idempotency_key = 'refund:' || p_capsule_id)
  then
    select * into v_bal from public.drop_balances where user_id = v_uid;

    -- A subscription refund after the subscription lapsed would vanish at the
    -- next rollover, so it lands in the permanent bucket instead. A failed
    -- upload must never silently cost the user a drop.
    v_target := case
      when v_bucket = 'subscription' and v_bal.subscription_status <> 'active'
        then 'purchased'
      else v_bucket
    end;

    update public.drop_balances
       set free_drops_remaining = free_drops_remaining + (case when v_target = 'free' then 1 else 0 end),
           -- Capped: a refund must never inflate the monthly bucket past its grant.
           subscription_drops_remaining = case
             when v_target = 'subscription'
               then least(subscription_drops_remaining + 1, subscription_monthly_grant)
             else subscription_drops_remaining end,
           purchased_drops_remaining = purchased_drops_remaining + (case when v_target = 'purchased' then 1 else 0 end),
           updated_at = now()
     where user_id = v_uid;

    insert into public.drop_ledger (user_id, delta, bucket, reason, capsule_id, idempotency_key, metadata)
    values (v_uid, 1, v_target, 'capsule_refund', p_capsule_id,
            'refund:' || p_capsule_id,
            jsonb_build_object('capsule_id', p_capsule_id::text, 'origin_bucket', v_bucket));

    v_refunded := true;
  end if;

  delete from public.time_capsules where id = p_capsule_id and creator_id = v_uid;

  select * into v_bal from public.drop_balances where user_id = v_uid;
  return query select
    v_refunded,
    coalesce(v_target, v_bucket),
    v_bal.free_drops_remaining,
    v_bal.subscription_drops_remaining,
    v_bal.purchased_drops_remaining,
    v_bal.free_drops_remaining + v_bal.subscription_drops_remaining + v_bal.purchased_drops_remaining;
end;
$$;

revoke all on function public.discard_capsule(uuid) from public, anon;
grant execute on function public.discard_capsule(uuid) to authenticated;

-- ── Backfill ─────────────────────────────────────────────────────────────────
-- Existing users keep whatever free allowance they had not yet spent, with a
-- matching ledger row so `sum(delta) = balance` holds from day one.
do $$
declare
  v_limit int;
  v_grant int;
  r       record;
begin
  select coalesce((select value::int from public.system_settings where key = 'free_drop_limit'), 1) into v_limit;
  select coalesce((select value::int from public.system_settings where key = 'subscription_monthly_grant'), 10) into v_grant;

  for r in
    select us.user_id, greatest(0, v_limit - coalesce(us.free_drops_used, 0)) as remaining
      from public.user_settings us
  loop
    insert into public.drop_balances (user_id, free_drops_remaining, subscription_monthly_grant)
    values (r.user_id, r.remaining, v_grant)
    on conflict (user_id) do nothing;

    insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key)
    values (r.user_id, r.remaining, 'free', 'signup_free', 'signup_free:' || r.user_id)
    on conflict (idempotency_key) do nothing;
  end loop;
end $$;
