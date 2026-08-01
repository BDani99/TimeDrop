/// Table/bucket/RPC names used across the app — not secrets, just kept in
/// one place so a rename only touches this file.
class SupabaseConstants {
  SupabaseConstants._();

  static const String timeCapsulesTable = 'time_capsules';
  static const String userSettingsTable = 'user_settings';
  static const String savedMemoriesTable = 'saved_memories';
  static const String receivedCapsulesTable = 'received_capsules';
  static const String systemSettingsTable = 'system_settings';
  static const String feedbackTable = 'feedback';

  static const String capsuleMediaBucket = 'capsule-media';

  static const String getCapsuleByShareIdRpc = 'get_capsule_by_share_id';
  static const String updateSentCapsuleMetaRpc = 'update_sent_capsule_meta';
  static const String requestMergeGrantRpc = 'request_merge_grant';
  static const String ensureOwnDropBalanceRpc = 'ensure_own_drop_balance';
  static const String getDropStateRpc = 'get_drop_state';
  static const String createPendingCapsuleRpc = 'create_pending_capsule';
  static const String discardCapsuleRpc = 'discard_capsule';
  static const String validateReviewerPasscodeRpc = 'validate_reviewer_passcode';

  static const String reviewerFlagsTable = 'reviewer_flags';

  static const String mergeAnonymousAccountFunction = 'merge-anonymous-account';
  static const String deleteUserAccountFunction = 'delete-user-account';

  /// system_settings keys.
  static const String settingRadarZoneRadius = 'radar_zone_radius_meters';
  static const String settingUnlockProximity = 'unlock_proximity_meters';
  static const String settingFreeDropLimit = 'free_drop_limit';
  static const String settingRadarSwitchMeters = 'radar_switch_meters';
}
