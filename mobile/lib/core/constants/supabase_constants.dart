/// Table/bucket/RPC names used across the app — not secrets, just kept in
/// one place so a rename only touches this file.
class SupabaseConstants {
  SupabaseConstants._();

  static const String timeCapsulesTable = 'time_capsules';
  static const String userSettingsTable = 'user_settings';
  static const String savedMemoriesTable = 'saved_memories';
  static const String receivedCapsulesTable = 'received_capsules';
  static const String systemSettingsTable = 'system_settings';
  static const String deviceSubscriptionsTable = 'device_subscriptions';

  static const String capsuleMediaBucket = 'capsule-media';

  static const String getCapsuleByShareIdRpc = 'get_capsule_by_share_id';
  static const String getDeviceSubscriptionRpc = 'get_device_subscription';
  static const String setDeviceSubscriptionRpc = 'set_device_subscription';
  static const String incrementFreeDropsUsedRpc = 'increment_free_drops_used';

  static const String mergeAnonymousAccountFunction = 'merge-anonymous-account';

  /// system_settings keys.
  static const String settingRadarZoneRadius = 'radar_zone_radius_meters';
  static const String settingUnlockProximity = 'unlock_proximity_meters';
  static const String settingFreeDropLimit = 'free_drop_limit';
}
