/// One encrypted media blob referenced by a capsule's metadata.
class CapsuleMediaRef {
  const CapsuleMediaRef({required this.storagePath, required this.mimeType});

  final String storagePath;
  final String mimeType;

  factory CapsuleMediaRef.fromJson(Map<String, dynamic> json) {
    return CapsuleMediaRef(
      storagePath: json['storagePath'] as String,
      mimeType: json['mimeType'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'storagePath': storagePath, 'mimeType': mimeType};
}

/// Decrypted shape of a capsule's metadata JSON (the payload encrypted into
/// `time_capsules.encrypted_payload`). Never construct this from untrusted
/// input without going through `CryptoService.decryptMetadata` first.
///
/// v2 adds an optional text [note] and up to 3 [photos] alongside the video,
/// each its own encrypted blob under the same key (multi-blob design). v1
/// capsules (flat `storagePath`) still decode via the compatibility branch in
/// [fromJson].
class CapsuleMetadata {
  const CapsuleMetadata({
    required this.video,
    required this.durationMs,
    required this.capturedAt,
    this.note,
    this.photos = const [],
    this.coverPhotoIndex,
  });

  final CapsuleMediaRef video;
  final int durationMs;
  final DateTime capturedAt;
  final String? note;
  final List<CapsuleMediaRef> photos;

  /// Index into [photos] the sender marked as the cover/thumbnail, if any.
  final int? coverPhotoIndex;

  /// Back-compat helpers for callers that still think in terms of the single
  /// video blob.
  String get storagePath => video.storagePath;
  String get mimeType => video.mimeType;

  factory CapsuleMetadata.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as int? ?? 1;
    if (version >= 2) {
      return CapsuleMetadata(
        video: CapsuleMediaRef.fromJson(json['video'] as Map<String, dynamic>),
        durationMs: json['durationMs'] as int,
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        note: json['note'] as String?,
        photos: ((json['photos'] as List?) ?? const [])
            .map((p) => CapsuleMediaRef.fromJson(p as Map<String, dynamic>))
            .toList(),
        coverPhotoIndex: json['coverPhotoIndex'] as int?,
      );
    }
    // v1: flat storagePath/mimeType for a single video, no note/photos.
    return CapsuleMetadata(
      video: CapsuleMediaRef(
        storagePath: json['storagePath'] as String,
        mimeType: json['mimeType'] as String,
      ),
      durationMs: json['durationMs'] as int,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'video': video.toJson(),
        'durationMs': durationMs,
        'capturedAt': capturedAt.toIso8601String(),
        if (note != null && note!.isNotEmpty) 'note': note,
        if (photos.isNotEmpty) 'photos': photos.map((p) => p.toJson()).toList(),
        if (coverPhotoIndex != null) 'coverPhotoIndex': coverPhotoIndex,
      };
}
