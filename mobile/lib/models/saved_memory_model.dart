/// Sprint 3 "Keep this memory forever" record. See migration
/// `0005_saved_memories.sql` for the documented Zero-Knowledge trade-off of
/// storing `encryptionKey` server-side for opted-in saved copies only.
class SavedMemoryModel {
  const SavedMemoryModel({
    required this.id,
    required this.userId,
    required this.capsuleId,
    required this.encryptionKey,
    required this.savedAt,
  });

  final String id;
  final String userId;
  final String capsuleId;
  final String encryptionKey;
  final DateTime savedAt;

  factory SavedMemoryModel.fromJson(Map<String, dynamic> json) {
    return SavedMemoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      capsuleId: json['capsule_id'] as String,
      encryptionKey: json['encryption_key'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
    );
  }
}
