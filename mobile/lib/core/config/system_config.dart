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

  /// Below this the recipient's map gives way to the radar. See migration
  /// 0028 for why it is tunable.
  double radarSwitchMeters = AppConstants.radarSwitchMeters;

  /// Hysteresis band: once the radar is showing, the map only comes back above
  /// this. Without the gap, GPS jitter around the threshold would flip the
  /// whole screen back and forth every few seconds.
  double get mapReturnMeters => radarSwitchMeters * 1.3;

  // `free_drop_limit` is deliberately NOT mirrored here any more. The drop
  // allowance is enforced inside `create_pending_capsule`, and a client-side
  // copy could only ever disagree with the server that actually decides.

  void apply({
    double? radarZoneRadiusMeters,
    double? unlockProximityMeters,
    double? radarSwitchMeters,
  }) {
    if (radarZoneRadiusMeters != null && radarZoneRadiusMeters > 0) {
      this.radarZoneRadiusMeters = radarZoneRadiusMeters;
    }
    if (unlockProximityMeters != null && unlockProximityMeters > 0) {
      this.unlockProximityMeters = unlockProximityMeters;
    }
    if (radarSwitchMeters != null && radarSwitchMeters > 0) {
      this.radarSwitchMeters = radarSwitchMeters;
    }
  }
}
