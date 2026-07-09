import '../constants/app_constants.dart';

/// Runtime-tunable config sourced from the `system_settings` Supabase table,
/// loaded once at startup by [SystemSettingsService]. Kept as a plain
/// singleton (not a provider) so non-widget code — notably
/// [CapsuleProvider]'s proximity check — can read it without context
/// plumbing. Values default to the compile-time [AppConstants] and are
/// overwritten only when a successful fetch supplies a positive number.
class SystemConfig {
  SystemConfig._();

  static final SystemConfig instance = SystemConfig._();

  double radarZoneRadiusMeters = AppConstants.radarZoneRadiusMeters;
  double unlockProximityMeters = AppConstants.unlockProximityMeters;

  void apply({double? radarZoneRadiusMeters, double? unlockProximityMeters}) {
    if (radarZoneRadiusMeters != null && radarZoneRadiusMeters > 0) {
      this.radarZoneRadiusMeters = radarZoneRadiusMeters;
    }
    if (unlockProximityMeters != null && unlockProximityMeters > 0) {
      this.unlockProximityMeters = unlockProximityMeters;
    }
  }
}
