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
    this.status = 'ready',
    this.encryptedPayload,
    this.city,
  });

  final String id;
  final String shareId;
  final double latitude;
  final double longitude;
  final DateTime unlockTime;
  final DateTime createdAt;

  /// Reverse-geocoded drop-location label (cached); null if unknown/offline.
  /// Shown as the card title on the sender's Home screen.
  final String? city;

  /// Upload lifecycle: 'pending' (background upload in flight), 'ready', or
  /// 'failed'. Optimistic UI inserts the row 'pending' before the encrypted
  /// payload exists.
  final String status;
  final String? encryptedPayload;

  bool get isUnlocked => DateTime.now().toUtc().isAfter(unlockTime.toUtc());
  bool get isPending => status == 'pending';

  /// Returns a copy with the [city] label filled in (used after a lazy
  /// reverse-geocode backfill on the Home screen).
  CapsuleModel copyWithCity(String city) => copyWith(city: city);

  CapsuleModel copyWith({
    double? latitude,
    double? longitude,
    DateTime? unlockTime,
    String? city,
    String? status,
  }) =>
      CapsuleModel(
        id: id,
        shareId: shareId,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        unlockTime: unlockTime ?? this.unlockTime,
        createdAt: createdAt,
        status: status ?? this.status,
        encryptedPayload: encryptedPayload,
        city: city ?? this.city,
      );

  factory CapsuleModel.fromJson(Map<String, dynamic> json) {
    return CapsuleModel(
      id: json['id'] as String,
      shareId: json['share_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      unlockTime: DateTime.parse(json['unlock_time'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'ready',
      encryptedPayload: json['encrypted_payload'] as String?,
      city: json['city'] as String?,
    );
  }
}
