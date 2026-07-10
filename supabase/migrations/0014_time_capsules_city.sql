-- HomeScreen (home.md v1.2): the sender's own capsule cards now show the
-- drop location as their title (e.g. "Paris" / "1st District") instead of the
-- raw share code. The label is reverse-geocoded on-device from the capsule's
-- lat/lng and cached here — mirroring received_capsules.city (migration 0013).
-- Nullable: geocoding can fail offline / return no result.
alter table public.time_capsules
  add column if not exists city text;
