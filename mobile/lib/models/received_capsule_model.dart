/// A capsule the current user has resolved as a *recipient* — tracked from
/// the moment a share link/code is first seen (clipboard auto-detect or
/// manual entry in the Gallery), independent of unlock status. Persists
/// across app sessions for anonymous accounts too, since it's keyed by
/// `auth.uid()` regardless of whether that user is linked.
class ReceivedCapsuleModel {
  const ReceivedCapsuleModel({
    required this.id,
    required this.capsuleId,
    required this.shareId,
    required this.unlockTime,
    required this.latitude,
    required this.longitude,
    required this.isViewed,
    required this.firstSeenAt,
    this.encryptionKey,
  });

  final String id;
  final String capsuleId;
  final String shareId;
  final DateTime unlockTime;
  final double latitude;
  final double longitude;
  final bool isViewed;
  final DateTime firstSeenAt;

  /// Null when only a bare share code was entered — the decryption key
  /// lives solely in the share link's hash fragment (Zero-Knowledge
  /// design), so a code alone can never unlock the content.
  final String? encryptionKey;

  bool get hasKey => encryptionKey != null;
  bool get isUnlockTimeReached => DateTime.now().toUtc().isAfter(unlockTime.toUtc());

  factory ReceivedCapsuleModel.fromJson(Map<String, dynamic> json) {
    return ReceivedCapsuleModel(
      id: json['id'] as String,
      capsuleId: json['capsule_id'] as String,
      shareId: json['share_id'] as String,
      unlockTime: DateTime.parse(json['unlock_time'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isViewed: json['is_viewed'] as bool? ?? false,
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
      encryptionKey: json['encryption_key'] as String?,
    );
  }
}
