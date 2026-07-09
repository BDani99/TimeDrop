-- Runtime-tunable numeric settings the app reads at startup, editable from
-- the Supabase dashboard / SQL without shipping a new build. The mobile app
-- falls back to its hardcoded AppConstants defaults if this can't be read.
create table public.system_settings (
  key        text primary key,
  value      numeric not null,
  updated_at timestamptz not null default now()
);

alter table public.system_settings enable row level security;

-- Any authenticated (incl. anonymous) user may read config; nobody but the
-- service role / dashboard may write it (no INSERT/UPDATE/DELETE policy).
create policy "system_settings_read_all"
  on public.system_settings for select
  to authenticated
  using (true);

insert into public.system_settings (key, value) values
  ('radar_zone_radius_meters', 100),
  ('unlock_proximity_meters', 15)
on conflict (key) do nothing;
