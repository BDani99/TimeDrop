/// Decrypted shape of a capsule's metadata JSON (the payload encrypted into
/// `time_capsules.encrypted_payload`). Never construct this from untrusted
/// input without going through `CryptoService.decryptCapsule` first.
class CapsuleMetadata {
  const CapsuleMetadata({
    required this.storagePath,
    required this.mimeType,
    required this.durationMs,
    required this.capturedAt,
  });

  final String storagePath;
  final String mimeType;
  final int durationMs;
  final DateTime capturedAt;

  factory CapsuleMetadata.fromJson(Map<String, dynamic> json) {
    return CapsuleMetadata(
      storagePath: json['storagePath'] as String,
      mimeType: json['mimeType'] as String,
      durationMs: json['durationMs'] as int,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'storagePath': storagePath,
        'mimeType': mimeType,
        'durationMs': durationMs,
        'capturedAt': capturedAt.toIso8601String(),
      };
}
