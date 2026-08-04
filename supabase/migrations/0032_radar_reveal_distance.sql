-- The radar no longer replaces the recipient's map — it appears beneath it, and
-- the map stays visible the whole way in. That changes what this setting means:
-- it was the distance at which the screen *switched*, and it is now the
-- distance at which the radar *joins*.
--
-- Swapping the screen out at 100 m would have been disorienting, which is why
-- 0028 set it to 50. Adding an instrument at 100 m is just earlier feedback, so
-- the value moves up to match `radar_zone_radius_meters` — the radar, the
-- warming background and the haptic pulse now all begin at the same distance.
--
-- Without this the server would keep serving 50 and quietly override the app's
-- new compile-time default (AppConstants.radarSwitchMeters).

update public.system_settings
set value = 100
where key = 'radar_switch_meters';
