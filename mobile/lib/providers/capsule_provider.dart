import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/config/system_config.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_metadata.dart';
import '../models/capsule_model.dart';
import '../services/crypto_service.dart';
import '../services/geolocation_service.dart';
import '../services/media_cache_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/video_service.dart';

enum RadarPhase { locating, waiting, searching, unlocked }

/// Background-upload lifecycle for a just-created capsule (optimistic UI).
enum CapsuleUploadState { uploading, ready, failed }

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
  String? decryptedNote;
  List<Uint8List> decryptedPhotos = const [];
  double? distanceMeters;
  RadarPhase radarPhase = RadarPhase.locating;

  StreamSubscription<Position>? _positionSubscription;
  String? _pendingEncryptionKey;
  String? _recipientUserId;

  /// The encryption key for [activeCapsule], if one has been loaded via
  /// [loadCapsuleForRadar]. Exposed for Sprint 3's "keep this memory
  /// forever" flow, which persists it into `saved_memories`.
  String? get pendingEncryptionKey => _pendingEncryptionKey;

  /// Per-capsule background-upload state, so the sent list can show a
  /// "still uploading" / "failed" badge.
  final Map<String, CapsuleUploadState> _uploadStates = {};
  CapsuleUploadState uploadStateFor(String capsuleId) =>
      _uploadStates[capsuleId] ?? CapsuleUploadState.ready;

  /// Optimistic UI (Phase 2): reserve a share_id + pending row and return the
  /// share info IMMEDIATELY, then compress/encrypt/upload in the background.
  /// The heavy work never blocks the "Seal" tap → ShareScreen navigation.
  /// The key is generated up front so the link is valid instantly and the
  /// background task encrypts with the same key.
  Future<CapsuleShareInfo> reserveCapsule({
    required String mediaPath,
    required String mimeType,
    required int durationMs,
    required List<String> photoPaths,
    required double latitude,
    required double longitude,
    required DateTime unlockTime,
    required String creatorId,
    String? note,
    int? coverPhotoIndex,
  }) async {
    isCreating = true;
    notifyListeners();
    try {
      final keyUrlSafe = await CryptoService.generateKeyUrlSafe();

      String? shareId;
      String? capsuleId;
      var attempts = 0;
      while (capsuleId == null && attempts < AppConstants.shareIdMaxRetries) {
        final candidate = CryptoService.generateShareId();
        try {
          capsuleId = await SupabaseService.insertPendingCapsule(
            creatorId: creatorId,
            shareId: candidate,
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

      if (capsuleId == null || shareId == null) {
        throw const CapsuleException('Could not generate a unique share code. Please try again.');
      }

      await SupabaseService.markFreeDropUsed(creatorId);

      _uploadStates[capsuleId] = CapsuleUploadState.uploading;
      // Fire-and-forget: the provider is app-scoped, so this outlives the
      // navigation to ShareScreen / Home.
      unawaited(_processUploadInBackground(
        capsuleId: capsuleId,
        keyUrlSafe: keyUrlSafe,
        mediaPath: mediaPath,
        photoPaths: photoPaths,
        mimeType: mimeType,
        durationMs: durationMs,
        creatorId: creatorId,
        note: note,
        coverPhotoIndex: coverPhotoIndex,
      ));

      return CapsuleShareInfo(shareId: shareId, encryptionKey: keyUrlSafe);
    } finally {
      isCreating = false;
      notifyListeners();
    }
  }

  Future<void> _processUploadInBackground({
    required String capsuleId,
    required String keyUrlSafe,
    required String mediaPath,
    required List<String> photoPaths,
    required String mimeType,
    required int durationMs,
    required String creatorId,
    String? note,
    int? coverPhotoIndex,
  }) async {
    try {
      final compressedPath = await VideoService.compress(mediaPath);
      final encryptedPayload = await CryptoService.encryptAndUploadCapsule(
        keyUrlSafe: keyUrlSafe,
        videoPath: compressedPath,
        photoPaths: photoPaths,
        videoMimeType: mimeType,
        durationMs: durationMs,
        creatorId: creatorId,
        note: note,
        coverPhotoIndex: coverPhotoIndex,
      );
      await SupabaseService.updateCapsulePayload(
        capsuleId: capsuleId,
        encryptedPayload: encryptedPayload,
        status: 'ready',
      );
      _uploadStates[capsuleId] = CapsuleUploadState.ready;
    } catch (e) {
      _uploadStates[capsuleId] = CapsuleUploadState.failed;
      try {
        await SupabaseService.updateCapsulePayload(capsuleId: capsuleId, status: 'failed');
      } catch (_) {
        // Best-effort — the row simply stays 'pending' if this also fails.
      }
      debugPrint('Capsule background upload failed: $e');
    } finally {
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
    String? fromName,
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
        fromName: fromName,
      );

      radarPhase = capsule.isUnlocked ? RadarPhase.searching : RadarPhase.waiting;
      notifyListeners();
    } finally {
      isLoadingRadar = false;
      notifyListeners();
    }
  }

  /// Re-fetches the active capsule (used by RadarScreen to poll while a
  /// background upload is still 'pending', so the recipient's screen flips to
  /// the real radar once the upload lands).
  Future<void> refreshActiveCapsule() async {
    final capsule = activeCapsule;
    if (capsule == null) return;
    final fresh = await SupabaseService.fetchCapsuleByShareId(capsule.shareId);
    if (fresh == null) return;
    activeCapsule = fresh;
    if (!fresh.isPending && radarPhase == RadarPhase.locating) {
      radarPhase = fresh.isUnlocked ? RadarPhase.searching : RadarPhase.waiting;
    }
    notifyListeners();
  }

  DateTime? _fuzzyZoneEntry;

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

      // Fuzzy unlocking: track how long we've stayed within the loose zone.
      // If the device sits inside it long enough, allow the unlock even if
      // GPS never reaches the tight proximity (defeats GPS bounce near
      // buildings).
      final inFuzzyZone = meters <= AppConstants.fuzzyUnlockZoneMeters;
      if (inFuzzyZone) {
        _fuzzyZoneEntry ??= DateTime.now();
      } else {
        _fuzzyZoneEntry = null;
      }
      final fuzzyElapsed = _fuzzyZoneEntry == null
          ? Duration.zero
          : DateTime.now().difference(_fuzzyZoneEntry!);
      final fuzzyUnlockAllowed =
          inFuzzyZone && fuzzyElapsed >= AppConstants.fuzzyUnlockStableDuration;

      final withinProximity = meters <= SystemConfig.instance.unlockProximityMeters;

      if (capsule.isUnlocked && (withinProximity || fuzzyUnlockAllowed)) {
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
    decryptedNote = metadata.note;

    decryptedMediaBytes = await CryptoService.decryptBlob(
      storagePath: metadata.video.storagePath,
      encryptionKeyUrlSafe: key,
    );

    final photos = <Uint8List>[];
    for (final photo in metadata.photos) {
      photos.add(await CryptoService.decryptBlob(
        storagePath: photo.storagePath,
        encryptionKeyUrlSafe: key,
      ));
    }
    decryptedPhotos = photos;

    // Cache the decrypted content so the Vault can show the cover thumbnail
    // and replay this memory offline without re-downloading/decrypting.
    final videoBytes = decryptedMediaBytes;
    if (videoBytes != null) {
      await MediaCacheService.store(
        capsuleId: capsule.id,
        video: videoBytes,
        note: metadata.note,
        photos: photos,
        coverPhotoIndex: metadata.coverPhotoIndex,
      );
    }

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
