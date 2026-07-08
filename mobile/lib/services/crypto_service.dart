import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/crypto/aes_gcm_envelope.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_metadata.dart';
import 'storage_service.dart';

/// Capsule-level encrypt/decrypt orchestration: ties the pure crypto
/// primitives in [AesGcmEnvelope] together with [StorageService] and the
/// metadata JSON shape, per the two-envelope design (media blob + metadata).
class CryptoService {
  CryptoService._();

  static const _uuid = Uuid();

  /// Encrypts [mediaBytes] and uploads it, then returns the base64-encoded
  /// metadata envelope to store in `time_capsules.encrypted_payload`, plus
  /// the raw key bytes (URL-safe encoded) for the share link.
  static Future<CapsuleEncryptionResult> encryptAndUpload({
    required Uint8List mediaBytes,
    required String mimeType,
    required int durationMs,
    required String creatorId,
  }) async {
    final key = await AesGcmEnvelope.generateKey();

    final mediaEnvelope = await AesGcmEnvelope.encrypt(
      plaintext: mediaBytes,
      key: key,
    );

    final storagePath = '$creatorId/${_uuid.v4()}.enc';
    await StorageService.uploadEncrypted(
      storagePath: storagePath,
      encryptedBytes: mediaEnvelope,
    );

    final metadata = CapsuleMetadata(
      storagePath: storagePath,
      mimeType: mimeType,
      durationMs: durationMs,
      capturedAt: DateTime.now().toUtc(),
    );
    final metadataBytes = Uint8List.fromList(utf8.encode(jsonEncode(metadata.toJson())));
    final metadataEnvelope = await AesGcmEnvelope.encrypt(
      plaintext: metadataBytes,
      key: key,
    );

    final encryptionKey = await AesGcmEnvelope.keyToUrlSafeString(key);

    return CapsuleEncryptionResult(
      encryptedPayloadBase64: base64Encode(metadataEnvelope),
      encryptionKeyUrlSafe: encryptionKey,
    );
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

  /// Downloads and decrypts the raw media bytes referenced by [metadata].
  static Future<Uint8List> decryptMedia({
    required CapsuleMetadata metadata,
    required String encryptionKeyUrlSafe,
  }) async {
    final key = AesGcmEnvelope.keyFromUrlSafeString(encryptionKeyUrlSafe);
    final envelope = await StorageService.downloadEncrypted(metadata.storagePath);
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

class CapsuleEncryptionResult {
  const CapsuleEncryptionResult({
    required this.encryptedPayloadBase64,
    required this.encryptionKeyUrlSafe,
  });

  final String encryptedPayloadBase64;
  final String encryptionKeyUrlSafe;
}
