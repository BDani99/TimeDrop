-- The distance at which the recipient's screen stops being a map and becomes
-- the radar.
--
-- Above this the user needs *navigation* — a street map and a "Get Directions"
-- handoff to their maps app. Walking four kilometres along a compass needle is
-- not wayfinding. Below it a map stops helping: the last few metres are about
-- a specific tree or bench, which no street map resolves, so the radar's
-- bearing and quickening haptics take over.
--
-- 50 m matches AppConstants.radarClosingMeters, where the haptic pulse already
-- begins — so the picture changes and the phone starts beating in the same
-- moment. Tunable from here because the right number depends on GPS quality in
-- real neighbourhoods, which we will only learn after launch.
insert into public.system_settings (key, value)
values ('radar_switch_meters', 50)
on conflict (key) do nothing;
