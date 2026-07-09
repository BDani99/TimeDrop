-- Vault (galery.md): recipient cards show "From <name> · <city>".
-- from_name is captured from the share link's optional ?from= param (the
-- sender's display name); city is reverse-geocoded on-device from the
-- capsule's lat/lng and cached here. Both nullable — a link may omit the
-- name, and geocoding may fail offline.
alter table public.received_capsules
  add column if not exists from_name text,
  add column if not exists city text;

-- Sender's display name, persisted so the create screen prefills it and the
-- generated share link's ?from= is always populated.
alter table public.user_settings
  add column if not exists display_name text;
