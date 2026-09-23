-- resolveUserId() in the revenuecat-webhook function only checks that
-- app_user_id (or an alias) is a syntactically valid UUID — it never
-- confirms the id actually exists in auth.users. If RevenueCat ever reports
-- a well-formed UUID that isn't a real user (stale sandbox data, a deleted
-- account, cross-environment leakage), ensure_drop_balance's insert into
-- drop_balances throws a foreign-key violation. The edge function's generic
-- catch-all turns that into a 500, which RevenueCat reads as "retryable" and
-- retries forever, since this failure can never self-heal.
--
-- Same fix shape as the existing p_user is null / unknown-product checks
-- just above and below this one: fail fast with a terminal, non-retryable
-- status instead of letting the FK violation escape as an unhandled 500.
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

  if not exists (select 1 from auth.users where id = p_user) then
    return 'user_not_found';
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
