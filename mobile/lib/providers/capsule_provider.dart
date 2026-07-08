import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_metadata.dart';
import '../models/capsule_model.dart';
import '../services/crypto_service.dart';
import '../services/geolocation_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

enum RadarPhase { locating, waiting, searching, unlocked }

/// Owns both halves of the capsule lifecycle: Sprint 1 creation (encrypt +
/// upload + insert) and Sprint 2 retrieval (RPC lookup + distance stream +
/// decrypt). Kept as one provider because both halves share the same
/// [CryptoService]/[CapsuleModel] vocabulary and a recipient can also be a
/// sender in the same session.
class CapsuleProvider extends ChangeNotifier {
  bool isCreating = false;
  bool isLoadingRadar = false;

  CapsuleModel? activeCapsule;
  CapsuleMetadata? decryptedMetadata;
  Uint8List? decryptedMediaBytes;
  double? distanceMeters;
  RadarPhase radarPhase = RadarPhase.locating;

  StreamSubscription<Position>? _positionSubscription;
  String? _pendingEncryptionKey;
  String? _recipientUserId;

  /// The encryption key for [activeCapsule], if one has been loaded via
  /// [loadCapsuleForRadar]. Exposed for Sprint 3's "keep this memory
  /// forever" flow, which persists it into `saved_memories`.
  String? get pendingEncryptionKey => _pendingEncryptionKey;

  /// Sprint 1: encrypts [mediaBytes], uploads it, and creates the DB row.
  /// Returns the share id + encryption key on success — the caller (e.g.
  /// ShareScreen) builds the final URL via `ShareService.buildShareUrl`,
  /// which also has access to the sender's display name for `?from=`.
  Future<CapsuleShareInfo> createCapsule({
    required Uint8List mediaBytes,
    required String mimeType,
    required int durationMs,
    required double latitude,
    required double longitude,
    required DateTime unlockTime,
    required String creatorId,
  }) async {
    isCreating = true;
    notifyListeners();
    try {
      final encryption = await CryptoService.encryptAndUpload(
        mediaBytes: mediaBytes,
        mimeType: mimeType,
        durationMs: durationMs,
        creatorId: creatorId,
      );

      String? shareId;
      var attempts = 0;
      while (shareId == null && attempts < AppConstants.shareIdMaxRetries) {
        final candidate = CryptoService.generateShareId();
        try {
          await SupabaseService.insertCapsule(
            creatorId: creatorId,
            shareId: candidate,
            encryptedPayload: encryption.encryptedPayloadBase64,
            latitude: latitude,
            longitude: longitude,
            unlockTime: unlockTime,
          );
          shareId = candidate;
        } on Exception catch (e) {
          attempts++;
          final isUniqueViolation = e.toString().contains('23505');
          if (!isUniqueViolation || attempts >= AppConstants.shareIdMaxRetries) {
            throw CapsuleException('Could not save your capsule.', cause: e);
          }
        }
      }

      if (shareId == null) {
        throw const CapsuleException('Could not generate a unique share code. Please try again.');
      }

      await SupabaseService.markFreeDropUsed(creatorId);

      return CapsuleShareInfo(
        shareId: shareId,
        encryptionKey: encryption.encryptionKeyUrlSafe,
      );
    } finally {
      isCreating = false;
      notifyListeners();
    }
  }

  /// Sprint 2: resolves a share link into a capsule row, decrypting the
  /// metadata immediately if already unlocked (so callers can offer instant
  /// download) or storing the key for later once proximity/time conditions
  /// are met. Also tracks the capsule into the recipient's Gallery
  /// (`received_capsules`) — this happens for every resolved link,
  /// regardless of unlock status, and works for anonymous accounts too
  /// since it's keyed purely by `auth.uid()`.
  Future<void> loadCapsuleForRadar({
    required String shareId,
    required String encryptionKey,
    required String recipientUserId,
  }) async {
    isLoadingRadar = true;
    radarPhase = RadarPhase.locating;
    notifyListeners();
    try {
      final capsule = await SupabaseService.fetchCapsuleByShareId(shareId);
      if (capsule == null) {
        throw const CapsuleException('This memory could not be found.');
      }
      activeCapsule = capsule;
      _pendingEncryptionKey = encryptionKey;
      _recipientUserId = recipientUserId;

      await NotificationService.scheduleUnlockReminder(
        capsuleId: capsule.id,
        unlockTime: capsule.unlockTime,
      );

      await SupabaseService.upsertReceivedCapsule(
        userId: recipientUserId,
        capsuleId: capsule.id,
        shareId: capsule.shareId,
        unlockTime: capsule.unlockTime,
        latitude: capsule.latitude,
        longitude: capsule.longitude,
        encryptionKey: encryptionKey,
      );

      radarPhase = capsule.isUnlocked ? RadarPhase.searching : RadarPhase.waiting;
      notifyListeners();
    } finally {
      isLoadingRadar = false;
      notifyListeners();
    }
  }

  /// Starts the continuous GPS stream for the Radar UI. Caller (RadarScreen)
  /// MUST call [stopWatchingPosition] in its `dispose()`.
  void startWatchingPosition() {
    final capsule = activeCapsule;
    if (capsule == null) return;

    _positionSubscription?.cancel();
    _positionSubscription = GeolocationService.watchPosition().listen((position) async {
      final meters = GeolocationService.distanceInMeters(
        startLat: position.latitude,
        startLng: position.longitude,
        endLat: capsule.latitude,
        endLng: capsule.longitude,
      );
      distanceMeters = meters;

      if (capsule.isUnlocked && meters <= AppConstants.unlockProximityMeters) {
        if (radarPhase != RadarPhase.unlocked) {
          radarPhase = RadarPhase.unlocked;
          await _decryptActiveCapsule();
        }
      } else if (capsule.isUnlocked) {
        radarPhase = RadarPhase.searching;
      }
      notifyListeners();
    });
  }

  void stopWatchingPosition() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  Future<void> _decryptActiveCapsule() async {
    final capsule = activeCapsule;
    final key = _pendingEncryptionKey;
    if (capsule?.encryptedPayload == null || key == null) return;

    final metadata = await CryptoService.decryptMetadata(
      encryptedPayloadBase64: capsule!.encryptedPayload!,
      encryptionKeyUrlSafe: key,
    );
    decryptedMetadata = metadata;

    final mediaBytes = await CryptoService.decryptMedia(
      metadata: metadata,
      encryptionKeyUrlSafe: key,
    );
    decryptedMediaBytes = mediaBytes;

    final userId = _recipientUserId;
    if (userId != null) {
      await SupabaseService.markReceivedCapsuleViewed(userId: userId, capsuleId: capsule.id);
    }
  }

  @override
  void dispose() {
    stopWatchingPosition();
    super.dispose();
  }
}

class CapsuleShareInfo {
  const CapsuleShareInfo({required this.shareId, required this.encryptionKey});

  final String shareId;
  final String encryptionKey;
}
