-- Device-keyed (mock) subscription state so "Restore purchases" can survive
-- a reinstall / new anonymous account: the device_hash is a high-entropy
-- value the client generates once and keeps in secure storage. Same trust
-- model as share_id — access is only ever through the two SECURITY DEFINER
-- RPCs below (never a direct table scan), so a guessable device_hash isn't
-- exposed and one user can't enumerate others.
--
-- Mock note: in production the source of truth for entitlements would be
-- RevenueCat/StoreKit; this table stands in for that while payments are
-- mocked. A client can only assert premium for its own (secret) device_hash.
create table public.device_subscriptions (
  device_hash       text primary key,
  is_premium        boolean not null default false,
  subscription_type text,
  subscribed_at     timestamptz,
  updated_at        timestamptz not null default now()
);

alter table public.device_subscriptions enable row level security;
-- Intentionally no table policies; all access via the RPCs below.

create or replace function public.get_device_subscription(p_device_hash text)
returns table (is_premium boolean, subscription_type text)
language sql
security definer
set search_path = public
stable
as $$
  select ds.is_premium, ds.subscription_type
  from public.device_subscriptions ds
  where ds.device_hash = p_device_hash
  limit 1;
$$;

revoke all on function public.get_device_subscription(text) from public;
revoke all on function public.get_device_subscription(text) from anon;
grant execute on function public.get_device_subscription(text) to authenticated;

create or replace function public.set_device_subscription(
  p_device_hash text,
  p_is_premium boolean,
  p_subscription_type text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.device_subscriptions
    (device_hash, is_premium, subscription_type, subscribed_at, updated_at)
  values (
    p_device_hash,
    p_is_premium,
    p_subscription_type,
    case when p_is_premium then now() else null end,
    now()
  )
  on conflict (device_hash) do update set
    is_premium = excluded.is_premium,
    subscription_type = excluded.subscription_type,
    subscribed_at = coalesce(public.device_subscriptions.subscribed_at, excluded.subscribed_at),
    updated_at = now();
$$;

revoke all on function public.set_device_subscription(text, boolean, text) from public;
revoke all on function public.set_device_subscription(text, boolean, text) from anon;
grant execute on function public.set_device_subscription(text, boolean, text) to authenticated;
