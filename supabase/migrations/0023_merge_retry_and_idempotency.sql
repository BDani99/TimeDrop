-- Two defects found while testing the merge path.
--
-- 1. `merge_drop_balances` was not idempotent. Its ledger row carried an
--    idempotency key, but the BALANCE update did not check it, so a second run
--    added the source's purchased drops all over again (5 + 2 = 7, then 12).
--
-- 2. `consume_merge_grant` burned the token before the merge did its work.
--    If a later step failed, the client's retry — which reuses the same token,
--    deliberately, so a retry survives an app restart — was rejected with 403
--    and the user's memories stayed stranded. Exactly the failure the retry
--    exists to recover from.
--
-- The fix for (2) records WHICH account claimed the grant and lets that same
-- account re-consume it while it is still within its TTL. The security
-- property is unchanged: only the holder of a token minted by the source
-- account can merge, and only the target that first claimed it may retry.
-- This is safe precisely because every step of the merge is now idempotent.

alter table public.merge_grants
  add column if not exists consumed_by uuid references auth.users(id) on delete set null;

create or replace function public.consume_merge_grant(
  p_token           text,
  p_expected_source uuid,
  p_target          uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_token is null or p_expected_source is null then
    return false;
  end if;

  -- First claim: burn it and record the claimant.
  update public.merge_grants
     set consumed_at = now(),
         consumed_by = coalesce(p_target, consumed_by)
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
     and source_user_id = p_expected_source
     and consumed_at is null
     and expires_at > now()
  returning id into v_id;

  if v_id is not null then
    return true;
  end if;

  -- Retry by the same claimant, still inside the TTL. Without this a merge
  -- that failed halfway could never be finished.
  if p_target is not null then
    select id into v_id
      from public.merge_grants
     where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
       and source_user_id = p_expected_source
       and consumed_by = p_target
       and expires_at > now();
  end if;

  return v_id is not null;
end;
$$;

revoke all on function public.consume_merge_grant(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.consume_merge_grant(text, uuid, uuid) to service_role;

-- The two-argument version is superseded; drop it so no caller can reach the
-- variant that cannot record a claimant.
drop function if exists public.consume_merge_grant(text, uuid);

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
  v_key    text;
begin
  if p_source = p_target then return; end if;

  v_key := 'merge:' || p_source || ':' || p_target;

  -- Idempotency guard. A merge that has already been applied must never be
  -- applied again: purchased drops are additive, so a second run would credit
  -- the source's packs twice.
  if exists (select 1 from public.drop_ledger where idempotency_key = v_key) then
    return;
  end if;

  perform public.ensure_drop_balance(p_target);

  select * into v_src from public.drop_balances where user_id = p_source;
  if not found then return; end if;
  select * into v_tgt from public.drop_balances where user_id = p_target for update;

  select coalesce((select value::int from public.system_settings where key = 'free_drop_limit'), 1)
    into v_limit;

  v_before := v_tgt.free_drops_remaining + v_tgt.subscription_drops_remaining
            + v_tgt.purchased_drops_remaining;

  -- Carries an unused free drop across, capped at the allowance so linking can
  -- never MINT one.
  v_free  := least(v_tgt.free_drops_remaining + v_src.free_drops_remaining, v_limit);
  -- Always additive: both sides were paid for.
  v_purch := v_tgt.purchased_drops_remaining + v_src.purchased_drops_remaining;

  if coalesce(v_src.subscription_expires_at, '-infinity'::timestamptz)
     > coalesce(v_tgt.subscription_expires_at, '-infinity'::timestamptz)
  then
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

  -- Always written, even when the net delta is zero, so the guard above is an
  -- exact record of "this merge has run" rather than a proxy for it.
  insert into public.drop_ledger (user_id, delta, bucket, reason, idempotency_key, metadata)
  values (p_target, v_after - v_before, 'purchased', 'merge_transfer', v_key,
          jsonb_build_object('source_user_id', p_source::text))
  on conflict (idempotency_key) do nothing;
end;
$$;

revoke all on function public.merge_drop_balances(uuid, uuid) from public, anon, authenticated;
grant execute on function public.merge_drop_balances(uuid, uuid) to service_role;
