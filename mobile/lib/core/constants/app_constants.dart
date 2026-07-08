/// App-wide, non-secret constants. Values here are baked into the share
/// link format and the Radar/proximity UX — changing them changes behavior
/// for every capsule already shared with the old values, so treat them as
/// stable once the app ships.
class AppConstants {
  AppConstants._();

  static const String appName = 'TimeDrop';

  /// Base host for generated share links. MUST match the Vercel project
  /// slug decided for `web/` (see terv.md §2 and the plan's naming decision).
  static const String shareBaseUrl = 'https://timedrop.vercel.app';

  /// Radar UI outer blur zone radius, in meters.
  static const double radarZoneRadiusMeters = 100;

  /// Distance at which the capsule unlocks (haptic + decrypt + play).
  static const double unlockProximityMeters = 15;

  /// Max video recording duration for CameraScreen.
  static const Duration maxRecordingDuration = Duration(seconds: 60);

  /// Length of the generated share_id (Crockford Base32).
  static const int shareIdLength = 6;
  static const String shareIdAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const int shareIdMaxRetries = 5;

  /// Free tier: one capsule before requiring Premium.
  static const int freeDropLimit = 1;

  /// Premium monthly allowances (PaywallScreen copy).
  static const int premiumMonthlyVideoLimit = 3;
  static const int premiumMonthlyPhotoLimit = 10;

  /// Reviewer bypass: tap count on the paywall title before the password
  /// field appears (App Store / Play reviewer QA path).
  static const int reviewerBypassTapCount = 10;
}
