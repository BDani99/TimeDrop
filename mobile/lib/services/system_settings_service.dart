import '../core/config/system_config.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Loads the runtime `system_settings` values into [SystemConfig] at startup.
/// Failure is non-fatal: the app keeps the compile-time defaults.
class SystemSettingsService {
  SystemSettingsService._();

  static Future<void> fetch() async {
    try {
      // This runs inline in MainRouter's bootstrap (see app_router.dart) —
      // unbounded, a stalled connection here would hang the splash screen
      // even though a failure is meant to be harmless (SystemConfig keeps
      // its defaults).
      final settings =
          await SupabaseService.fetchSystemSettings().timeout(AppConstants.dbCallTimeout);
      SystemConfig.instance.apply(
        radarZoneRadiusMeters: settings[SupabaseConstants.settingRadarZoneRadius],
        unlockProximityMeters: settings[SupabaseConstants.settingUnlockProximity],
        radarSwitchMeters: settings[SupabaseConstants.settingRadarSwitchMeters],
      );
    } catch (_) {
      // Non-fatal — SystemConfig keeps its AppConstants defaults.
    }
  }
}
