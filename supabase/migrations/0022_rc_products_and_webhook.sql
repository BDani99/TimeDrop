-- RevenueCat integration: the product catalogue the webhook maps purchases
-- through, an idempotency log for incoming events, and the single transactional
-- entry point that applies an event to a user's drop balance.
--
-- WHY THE WEBHOOK CALLS ONE SQL FUNCTION
-- --------------------------------------
-- Applying an event means touching drop_balances AND drop_ledger together. Done
-- as a sequence of PostgREST calls from the Edge Function, a mid-way failure
-- leaves a credited balance with no ledger row (or the reverse) and the
-- `sum(delta) = balance` invariant breaks silently. One SECURITY DEFINER
-- function means one transaction.
--
-- WHY DROP PACKS ARE NOT AN ENTITLEMENT
-- -------------------------------------
-- Consumable packs are deliberately NOT attached to the `pro` entitlement in
-- RevenueCat. If they were, `entitlements.active` would be non-empty for
-- someone who merely bought a one-off pack, and the app would treat them as a
-- subscriber. Packs are tracked here, in our own ledger.

-- ── Product catalogue ────────────────────────────────────────────────────────
create table public.drop_products (
  product_id    text primary key,
  kind          text    not null check (kind in ('subscription', 'pack')),
  -- For a pack: how many drops it grants. For a subscription: the monthly grant.
  drops_granted integer not null check (drops_granted > 0),
  is_active     boolean not null default true
);

alter table public.drop_products enable row level security;

-- Readable by signed-in clients so the paywall can label packs without
-- hardcoding sizes. Contains no secrets. No write policies.
create policy "drop_products_select_all"
  on public.drop_products for select
  to authenticated
  using (true);

revoke insert, update, delete on table public.drop_products from anon, authenticated;

-- Both stores' identifiers. Play sometimes reports a subscription without its
-- base-plan suffix, so the bare id is mapped too.
insert into public.drop_products (product_id, kind, drops_granted) values
  ('com.timedrop.pro.monthly', 'subscription', 10),
  ('com.timedrop.pro.annual',  'subscription', 10),
  ('timedrop_pro:monthly',     'subscription', 10),
  ('timedrop_pro:annual',      'subscription', 10),
  ('timedrop_pro',             'subscription', 10),
  -- RevenueCat Test Store products, so sandbox testing works before the real
  -- store SKUs exist.
  ('monthly',                  'subscription', 10),
  ('yearly',                   'subscription', 10),
  ('com.timedrop.drops.1',  'pack',  1),
  ('com.timedrop.drops.2',  'pack',  2),
  ('com.timedrop.drops.3',  'pack',  3),
  ('com.timedrop.drops.5',  'pack',  5),
  ('com.timedrop.drops.10', 'pack', 10),
  ('drops_1',  'pack',  1),
  ('drops_2',  'pack',  2),
  ('drops_3',  'pack',  3),
  ('drops_5',  'pack',  5),
  ('drops_10', 'pack', 10)
on conflict (product_id) do nothing;

-- ── Webhook idempotency log ──────────────────────────────────────────────────
-- RevenueCat retries any event we do not answer with a 2xx, so the same
-- delivery can arrive several times. The primary key is the guard.
create table public.rc_webhook_events (
  event_id    text primary key,
  event_type  text not null,
  app_user_id uuid,
  product_id  text,
  environment text,
  status      text not null,
  payload     jsonb not null,
  received_at timestamptz not null default now()
);

create index rc_webhook_events_received_idx on public.rc_webhook_events (received_at desc);

alter table public.rc_webhook_events enable row level security;
-- No policies: service role only. Contains full purchase payloads.
revoke all on table public.rc_webhook_events from anon, authenticated;

-- ── Event application ────────────────────────────────────────────────────────
create or replace function public.rc_apply_event(
  p_event_id     text,
  p_event_type   text,
  p_user         uuid,
  p_product_id   text,
  p_purchased_at timestamptz,
  p_expires_at   timestamptz
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kind  text;
  v_grant int;
  v_bal   public.drop_balances%rowtype;
begin
  if p_user is null then
    return 'unmapped_user';
  end if;

  perform public.ensure_drop_balance(p_user);

  select kind, drops_granted into v_kind, v_grant
    from public.drop_products
   where product_id = p_product_id and is_active;

  -- Events that carry a product we do not know about are an operations
  -- problem (a missing catalogue row), not something a retry will fix.
  if v_kind is null and p_event_type in (
    'INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'SUBSCRIPTION_EXTENDED',
    'PRODUCT_CHANGE', 'NON_RENEWING_PURCHASE', 'CANCELLATION'
  ) then
    return 'unknown_product';
  end if;

  select * into v_bal from public.drop_balances where user_id = p_user for update;

  -- ── One-off drop packs ─────────────────────────────────────────────────────
  if v_kind = 'pack' then
    if p_event_type = 'NON_RENEWING_PURCHASE' then
      update public.drop_balances
         set purchased_drops_remaining = purchased_drops_remaining + v_grant,
             updated_at = now()
       where user_id = p_user;

      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
      values (p_user, v_grant, 'purchased', 'pack_purchase', 'rc:' || p_event_id,
              jsonb_build_object('product_id', p_product_id))
      on conflict (idempotency_key) do nothing;
      return 'applied';

    elsif p_event_type = 'CANCELLATION' then
      -- A cancelled one-off purchase is a store refund: claw the drops back,
      -- but never below zero — they may already have been spent.
      update public.drop_balances
         set purchased_drops_remaining = greatest(0, purchased_drops_remaining - v_grant),
             updated_at = now()
       where user_id = p_user;

      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
      select p_user,
             -least(v_grant, v_bal.purchased_drops_remaining),
             'purchased', 'pack_refund', 'rc:' || p_event_id,
             jsonb_build_object('product_id', p_product_id)
      on conflict (idempotency_key) do nothing;
      return 'applied';
    end if;

    return 'ignored';
  end if;

  -- ── Subscriptions ──────────────────────────────────────────────────────────
  if p_event_type = 'INITIAL_PURCHASE' then
    -- Sets the cycle ANCHOR. This is the only event that may move it: the
    -- lazy rollover in _apply_subscription_cycle derives every monthly grant
    -- from this timestamp, so moving it on renewals would hand a monthly
    -- subscriber an extra reset each month.
    update public.drop_balances
       set subscription_status        = 'active',
           subscription_product_id    = p_product_id,
           subscription_auto_renew    = true,
           subscription_period_start  = coalesce(p_purchased_at, now()),
           subscription_expires_at    = p_expires_at,
           subscription_cycle_start   = null,
           subscription_monthly_grant = v_grant,
           updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type in ('RENEWAL', 'UNCANCELLATION', 'SUBSCRIPTION_EXTENDED') then
    update public.drop_balances
       set subscription_status     = 'active',
           subscription_auto_renew = true,
           subscription_expires_at = greatest(
             coalesce(p_expires_at, subscription_expires_at),
             coalesce(subscription_expires_at, p_expires_at)
           ),
           -- An annual subscriber emits one RENEWAL a year; the anchor stays
           -- put and the rollover keeps issuing a grant every month.
           subscription_period_start = coalesce(subscription_period_start, p_purchased_at, now()),
           updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type = 'PRODUCT_CHANGE' then
    update public.drop_balances
       set subscription_product_id    = p_product_id,
           subscription_expires_at    = coalesce(p_expires_at, subscription_expires_at),
           subscription_monthly_grant = v_grant,
           updated_at = now()
     where user_id = p_user;
    perform public._apply_subscription_cycle(p_user);
    return 'applied';

  elsif p_event_type = 'CANCELLATION' then
    -- Auto-renew turned off. Access, and the drops, run to the paid-for end
    -- date — nothing is taken away here.
    update public.drop_balances
       set subscription_auto_renew = false, updated_at = now()
     where user_id = p_user;
    return 'applied';

  elsif p_event_type = 'BILLING_ISSUE' then
    -- Grace period: _apply_subscription_cycle keeps granting until the grace
    -- window closes, so a failed card does not instantly strip a paying user.
    update public.drop_balances
       set subscription_status = 'grace', updated_at = now()
     where user_id = p_user;
    return 'applied';

  elsif p_event_type = 'EXPIRATION' then
    if v_bal.subscription_drops_remaining > 0 then
      insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key)
      values (p_user, -v_bal.subscription_drops_remaining, 'subscription',
              'subscription_expired', 'rc:' || p_event_id)
      on conflict (idempotency_key) do nothing;
    end if;
    -- Only the monthly bucket empties. Purchased packs and the free drop are
    -- untouched: they were not part of the subscription.
    update public.drop_balances
       set subscription_status           = 'expired',
           subscription_drops_remaining  = 0,
           subscription_auto_renew       = false,
           updated_at = now()
     where user_id = p_user;
    return 'applied';
  end if;

  return 'ignored';
end;
$$;

revoke all on function public.rc_apply_event(text, text, uuid, text, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.rc_apply_event(text, text, uuid, text, timestamptz, timestamptz)
  to service_role;

-- ── Balance merge (account linking) ──────────────────────────────────────────
-- Called by merge-anonymous-account. A single net ledger row on the target
-- keeps sum(delta) = balance intact once the source user (and its ledger) is
-- deleted by the cascade.
create or replace function public.merge_drop_balances(p_source uuid, p_target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_src    public.drop_balances%rowtype;
  v_tgt    public.drop_balances%rowtype;
  v_limit  int;
  v_before int;
  v_after  int;
  v_free   int;
  v_purch  int;
begin
  if p_source = p_target then return; end if;

  perform public.ensure_drop_balance(p_target);

  select * into v_src from public.drop_balances where user_id = p_source;
  if not found then return; end if;
  select * into v_tgt from public.drop_balances where user_id = p_target for update;

  select coalesce((select value::int from public.system_settings where key = 'free_drop_limit'), 1)
    into v_limit;

  v_before := v_tgt.free_drops_remaining + v_tgt.subscription_drops_remaining
            + v_tgt.purchased_drops_remaining;

  -- Carries an unused free drop across, but capped at the allowance so linking
  -- can never MINT one.
  v_free  := least(v_tgt.free_drops_remaining + v_src.free_drops_remaining, v_limit);
  -- Always additive: both sides were paid for.
  v_purch := v_tgt.purchased_drops_remaining + v_src.purchased_drops_remaining;

  if coalesce(v_src.subscription_expires_at, '-infinity'::timestamptz)
     > coalesce(v_tgt.subscription_expires_at, '-infinity'::timestamptz)
  then
    -- The source holds the better subscription: adopt it wholesale, anchor
    -- included, so the monthly rollover keeps working.
    update public.drop_balances
       set free_drops_remaining         = v_free,
           purchased_drops_remaining    = v_purch,
           subscription_drops_remaining = v_src.subscription_drops_remaining,
           subscription_status          = v_src.subscription_status,
           subscription_product_id      = v_src.subscription_product_id,
           subscription_auto_renew      = v_src.subscription_auto_renew,
           subscription_period_start    = v_src.subscription_period_start,
           subscription_expires_at      = v_src.subscription_expires_at,
           subscription_cycle_start     = v_src.subscription_cycle_start,
           subscription_monthly_grant   = v_src.subscription_monthly_grant,
           updated_at = now()
     where user_id = p_target;
  else
    update public.drop_balances
       set free_drops_remaining      = v_free,
           purchased_drops_remaining = v_purch,
           updated_at = now()
     where user_id = p_target;
  end if;

  select free_drops_remaining + subscription_drops_remaining + purchased_drops_remaining
    into v_after
    from public.drop_balances where user_id = p_target;

  if v_after <> v_before then
    insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
    values (p_target, v_after - v_before, 'purchased', 'merge_transfer',
            'merge:' || p_source || ':' || p_target,
            jsonb_build_object('source_user_id', p_source::text))
    on conflict (idempotency_key) do nothing;
  end if;
end;
$$;

revoke all on function public.merge_drop_balances(uuid, uuid) from public, anon, authenticated;
grant execute on function public.merge_drop_balances(uuid, uuid) to service_role;
