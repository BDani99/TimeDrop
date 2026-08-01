-- Removes the surfaces the drop ledger and RevenueCat replaced.
--
-- WHAT GOES, AND WHY IT IS SAFE
-- -----------------------------
-- `device_subscriptions` was a stand-in for real payments: a device-hash-keyed
-- boolean the client asserted about itself, which also powered a "Restore
-- purchases" that never touched a store. Entitlements now come from RevenueCat
-- and are mirrored per USER in `drop_balances`, so a device-keyed table is both
-- unused and the wrong shape (a subscription follows the account, not the
-- handset).
--
-- `user_settings.free_drop_used` / `.free_drops_used` were the old quota. Their
-- values were migrated into `drop_balances.free_drops_remaining` by 0020's
-- backfill, and enforcement moved into `create_pending_capsule`, which checks
-- and debits in one transaction. Nothing reads them any more — verified
-- against every function in the `public` schema and the whole Flutter client.
--
-- `increment_free_drops_used()` was the client-callable half of that old gate.
-- It is dropped rather than left in place: an RPC that still adjusts a
-- now-meaningless counter is an invitation to wire it back up by mistake.

drop function if exists public.increment_free_drops_used();

drop function if exists public.get_device_subscription(text);
drop function if exists public.set_device_subscription(text, boolean, text);

drop table if exists public.device_subscriptions;

alter table public.user_settings
  drop column if exists free_drop_used,
  drop column if exists free_drops_used;
