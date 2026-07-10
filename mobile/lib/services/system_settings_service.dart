import '../core/config/system_config.dart';
import '../core/constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Loads the runtime `system_settings` values into [SystemConfig] at startup.
/// Failure is non-fatal: the app keeps the compile-time defaults.
class SystemSettingsService {
  SystemSettingsService._();

  static Future<void> fetch() async {
    try {
      final settings = await SupabaseService.fetchSystemSettings();
      SystemConfig.instance.apply(
        radarZoneRadiusMeters: settings[SupabaseConstants.settingRadarZoneRadius],
        unlockProximityMeters: settings[SupabaseConstants.settingUnlockProximity],
        freeDropLimit: settings[SupabaseConstants.settingFreeDropLimit],
      );
    } catch (_) {
      // Non-fatal — SystemConfig keeps its AppConstants defaults.
    }
  }
}
