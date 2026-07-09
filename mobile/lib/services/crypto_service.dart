import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/crypto/aes_gcm_envelope.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_metadata.dart';
import 'storage_service.dart';

/// Capsule-level encrypt/decrypt orchestration: ties the pure crypto
/// primitives in [AesGcmEnvelope] together with [StorageService] and the
/// metadata JSON shape. Multi-blob design: the video and each photo are
/// their own encrypted Storage object under the *same* per-capsule key; the
/// note text + the blob paths live in the encrypted metadata envelope.
class CryptoService {
  CryptoService._();

  static const _uuid = Uuid();

  /// Generates a fresh per-capsule key, URL-safe encoded for the share link.
  /// Generated up front (before upload) so optimistic UI can show the link
  /// immediately while the background task encrypts with the same key.
  static Future<String> generateKeyUrlSafe() async {
    final key = await AesGcmEnvelope.generateKey();
    return AesGcmEnvelope.keyToUrlSafeString(key);
  }

  /// Encrypts + uploads the (already compressed) video and each photo as
  /// separate blobs, then returns the base64-encoded metadata envelope to
  /// store in `time_capsules.encrypted_payload`. Reads one file into memory
  /// at a time to keep the footprint small.
  static Future<String> encryptAndUploadCapsule({
    required String keyUrlSafe,
    required String videoPath,
    required List<String> photoPaths,
    required String videoMimeType,
    required int durationMs,
    required String creatorId,
    String? note,
    int? coverPhotoIndex,
  }) async {
    final key = AesGcmEnvelope.keyFromUrlSafeString(keyUrlSafe);

    final videoBytes = await File(videoPath).readAsBytes();
    final videoStoragePath = await _encryptAndUpload(videoBytes, key, creatorId);
    final videoRef = CapsuleMediaRef(storagePath: videoStoragePath, mimeType: videoMimeType);

    final photoRefs = <CapsuleMediaRef>[];
    for (final path in photoPaths) {
      final bytes = await File(path).readAsBytes();
      final storagePath = await _encryptAndUpload(bytes, key, creatorId);
      photoRefs.add(CapsuleMediaRef(storagePath: storagePath, mimeType: _photoMime(path)));
    }

    final metadata = CapsuleMetadata(
      video: videoRef,
      durationMs: durationMs,
      capturedAt: DateTime.now().toUtc(),
      note: (note != null && note.trim().isNotEmpty) ? note.trim() : null,
      photos: photoRefs,
      coverPhotoIndex: (coverPhotoIndex != null &&
              coverPhotoIndex >= 0 &&
              coverPhotoIndex < photoRefs.length)
          ? coverPhotoIndex
          : null,
    );
    final metadataBytes = Uint8List.fromList(utf8.encode(jsonEncode(metadata.toJson())));
    final metadataEnvelope = await AesGcmEnvelope.encrypt(plaintext: metadataBytes, key: key);
    return base64Encode(metadataEnvelope);
  }

  static Future<String> _encryptAndUpload(Uint8List bytes, SecretKey key, String creatorId) async {
    final envelope = await AesGcmEnvelope.encrypt(plaintext: bytes, key: key);
    final storagePath = '$creatorId/${_uuid.v4()}.enc';
    await StorageService.uploadEncrypted(storagePath: storagePath, encryptedBytes: envelope);
    return storagePath;
  }

  static String _photoMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// Decodes the metadata envelope from `encrypted_payload` using the key
  /// extracted from the share link.
  static Future<CapsuleMetadata> decryptMetadata({
    required String encryptedPayloadBase64,
    required String encryptionKeyUrlSafe,
  }) async {
    final key = AesGcmEnvelope.keyFromUrlSafeString(encryptionKeyUrlSafe);
    final Uint8List envelope;
    try {
      envelope = base64Decode(encryptedPayloadBase64);
    } catch (e) {
      throw CryptoException('The memory payload is corrupted.', cause: e);
    }
    final metadataBytes = await AesGcmEnvelope.decrypt(envelope: envelope, key: key);
    final json = jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
    return CapsuleMetadata.fromJson(json);
  }

  /// Downloads and decrypts a single encrypted blob (video or photo).
  static Future<Uint8List> decryptBlob({
    required String storagePath,
    required String encryptionKeyUrlSafe,
  }) async {
    final key = AesGcmEnvelope.keyFromUrlSafeString(encryptionKeyUrlSafe);
    final envelope = await StorageService.downloadEncrypted(storagePath);
    return AesGcmEnvelope.decrypt(envelope: envelope, key: key);
  }

  /// Generates a 6-character Crockford-Base32 share code using a
  /// cryptographically secure RNG.
  static String generateShareId() {
    final random = Random.secure();
    final alphabet = AppConstants.shareIdAlphabet;
    return List.generate(
      AppConstants.shareIdLength,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
