/// Row shape returned by the `get_capsule_by_share_id` RPC (and, for a
/// creator's own sent list, a direct `time_capsules` select). `encryptedPayload`
/// is null pre-unlock — the RPC withholds it until `unlockTime` has passed.
class CapsuleModel {
  const CapsuleModel({
    required this.id,
    required this.shareId,
    required this.latitude,
    required this.longitude,
    required this.unlockTime,
    required this.createdAt,
    this.encryptedPayload,
  });

  final String id;
  final String shareId;
  final double latitude;
  final double longitude;
  final DateTime unlockTime;
  final DateTime createdAt;
  final String? encryptedPayload;

  bool get isUnlocked => DateTime.now().toUtc().isAfter(unlockTime.toUtc());

  factory CapsuleModel.fromJson(Map<String, dynamic> json) {
    return CapsuleModel(
      id: json['id'] as String,
      shareId: json['share_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      unlockTime: DateTime.parse(json['unlock_time'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      encryptedPayload: json['encrypted_payload'] as String?,
    );
  }
}
