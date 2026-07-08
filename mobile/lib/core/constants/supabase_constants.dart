/// Table/bucket/RPC names used across the app — not secrets, just kept in
/// one place so a rename only touches this file.
class SupabaseConstants {
  SupabaseConstants._();

  static const String timeCapsulesTable = 'time_capsules';
  static const String userSettingsTable = 'user_settings';
  static const String savedMemoriesTable = 'saved_memories';
  static const String receivedCapsulesTable = 'received_capsules';

  static const String capsuleMediaBucket = 'capsule-media';

  static const String getCapsuleByShareIdRpc = 'get_capsule_by_share_id';

  static const String mergeAnonymousAccountFunction = 'merge-anonymous-account';
}
