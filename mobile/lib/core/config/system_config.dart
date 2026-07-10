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

  /// How many free drops each user gets before the paywall. Server-tunable
  /// via the `free_drop_limit` system setting.
  int freeDropLimit = AppConstants.freeDropLimit;

  void apply({
    double? radarZoneRadiusMeters,
    double? unlockProximityMeters,
    double? freeDropLimit,
  }) {
    if (radarZoneRadiusMeters != null && radarZoneRadiusMeters > 0) {
      this.radarZoneRadiusMeters = radarZoneRadiusMeters;
    }
    if (unlockProximityMeters != null && unlockProximityMeters > 0) {
      this.unlockProximityMeters = unlockProximityMeters;
    }
    if (freeDropLimit != null && freeDropLimit >= 0) {
      this.freeDropLimit = freeDropLimit.round();
    }
  }
}
