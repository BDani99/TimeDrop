import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/config/system_config.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../models/capsule_metadata.dart';
import '../models/capsule_model.dart';
import '../services/crypto_service.dart';
import '../services/geocoding_service.dart';
import '../services/geolocation_service.dart';
import '../services/media_cache_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../services/upload_queue_service.dart';
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
  double? userLatitude;
  double? userLongitude;
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

  /// Bumped whenever the set of sent capsules meaningfully changes: a new
  /// capsule is reserved, or a background upload reaches a terminal state
  /// (ready/failed). Screens that hold their own fetched list (e.g. HomeScreen)
  /// listen for changes to this to re-fetch, so the UI reflects a completed
  /// upload without a manual pull-to-refresh.
  int capsulesChangedTick = 0;

  void _bumpCapsulesChanged() {
    capsulesChangedTick++;
    notifyListeners();
  }

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

      await SupabaseService.incrementFreeDropsUsed();

      _uploadStates[capsuleId] = CapsuleUploadState.uploading;

      // Persist the job (and durable copies of the media) BEFORE kicking off
      // the upload, so it can be resumed if the app is killed mid-upload. The
      // background task reads from the durable copies, not the temp recording.
      // If the media file is unreachable, `enqueue` throws immediately — we
      // catch that here, mark the capsule as failed in the DB, and re-throw
      // so the UI can show the user a meaningful error.
      final UploadJob job;
      try {
        job = await UploadQueueService.enqueue(
          capsuleId: capsuleId,
          shareId: shareId,
          keyUrlSafe: keyUrlSafe,
          mediaPath: mediaPath,
          photoPaths: photoPaths,
          mimeType: mimeType,
          durationMs: durationMs,
          creatorId: creatorId,
          note: note,
          coverPhotoIndex: coverPhotoIndex,
        );
      } catch (e) {
        _uploadStates[capsuleId] = CapsuleUploadState.failed;
        await _safeMarkFailed(capsuleId);
        // Wrap as CapsuleException so the UI shows a readable message.
        throw CapsuleException(
          'The recording file could not be saved for upload. '
          'Please try recording again.',
          cause: e,
        );
      }

      // Fire-and-forget: the provider is app-scoped, so this outlives the
      // navigation to ShareScreen / Home.
      unawaited(_runUpload(job, keyUrlSafe));

      // Best-effort reverse-geocode of the drop location for the Home card
      // title. Non-blocking; Home also backfills any that miss this.
      unawaited(_setSentCityBestEffort(capsuleId, latitude, longitude));

      return CapsuleShareInfo(shareId: shareId, encryptionKey: keyUrlSafe);
    } finally {
      isCreating = false;
      // A new pending capsule now exists — let HomeScreen pick it up.
      _bumpCapsulesChanged();
    }
  }

  /// Re-drives every persisted upload job left over from a previous session
  /// (app was killed mid-upload). Call once at app start, after the provider
  /// and Supabase session exist. Jobs whose media no longer exists (and whose
  /// key was lost) are marked `failed` so the user sees a retryable state
  /// rather than an eternal "Uploading…".
  Future<void> resumePendingUploads() async {
    final jobs = await UploadQueueService.pending();
    for (final job in jobs) {
      final key = await UploadQueueService.keyFor(job.capsuleId);
      final mediaExists = await File(job.mediaPath).exists();
      if (key == null || !mediaExists) {
        _uploadStates[job.capsuleId] = CapsuleUploadState.failed;
        await _safeMarkFailed(job.capsuleId);
        continue;
      }
      _uploadStates[job.capsuleId] = CapsuleUploadState.uploading;
      unawaited(_runUpload(job, key));
    }
    if (jobs.isNotEmpty) _bumpCapsulesChanged();
  }

  /// Manually retries a previously-failed upload from its persisted job.
  Future<void> retryUpload(String capsuleId) async {
    final jobs = await UploadQueueService.pending();
    UploadJob? job;
    for (final j in jobs) {
      if (j.capsuleId == capsuleId) {
        job = j;
        break;
      }
    }
    final key = job == null ? null : await UploadQueueService.keyFor(capsuleId);
    if (job == null || key == null || !await File(job.mediaPath).exists()) {
      // Nothing left to retry with — leave it failed and drop the dead job.
      _uploadStates[capsuleId] = CapsuleUploadState.failed;
      await UploadQueueService.remove(capsuleId);
      _bumpCapsulesChanged();
      return;
    }
    _uploadStates[capsuleId] = CapsuleUploadState.uploading;
    await SupabaseService.updateCapsulePayload(capsuleId: capsuleId, status: 'pending');
    _bumpCapsulesChanged();
    unawaited(_runUpload(job, key));
  }

  /// Runs (or re-runs) the compress → encrypt → upload → finalize pipeline for
  /// a persisted [job]. The whole chain is bounded by [AppConstants.uploadTimeout]
  /// so a stalled network request surfaces as a retryable `failed` state
  /// instead of hanging on `pending` forever. On success the job (and its
  /// durable media copies) is removed from the queue.
  Future<void> _runUpload(UploadJob job, String keyUrlSafe) async {
    await UploadQueueService.markAttempt(job.capsuleId);
    try {
      // Verify the durable media copy exists before starting the heavy pipeline.
      // If it disappeared (OS cleanup, failed copy), surface a clear error now
      // rather than an opaque failure deep inside the crypto/upload chain.
      final mediaFile = File(job.mediaPath);
      if (!await mediaFile.exists()) {
        throw StateError(
          'Media file missing at "${job.mediaPath}". '
          'The recording was lost before the upload could start.',
        );
      }

      final encryptedPayload = await () async {
        final compressedPath = await VideoService.compress(job.mediaPath);
        return CryptoService.encryptAndUploadCapsule(
          keyUrlSafe: keyUrlSafe,
          videoPath: compressedPath,
          photoPaths: job.photoPaths,
          videoMimeType: job.mimeType,
          durationMs: job.durationMs,
          creatorId: job.creatorId,
          note: job.note,
          coverPhotoIndex: job.coverPhotoIndex,
        );
      }()
          .timeout(AppConstants.uploadTimeout);

      await SupabaseService.updateCapsulePayload(
        capsuleId: job.capsuleId,
        encryptedPayload: encryptedPayload,
        status: 'ready',
      );
      _uploadStates[job.capsuleId] = CapsuleUploadState.ready;
      await UploadQueueService.remove(job.capsuleId);
    } catch (e, st) {
      _uploadStates[job.capsuleId] = CapsuleUploadState.failed;
      // Log the full stack trace so we can diagnose the root cause.
      debugPrint('Capsule background upload failed (${job.capsuleId}): $e\n$st');
      // The job stays in the queue so the user (or the next launch) can retry.
      await _safeMarkFailed(job.capsuleId);
    } finally {
      _bumpCapsulesChanged();
    }
  }

  /// Best-effort flip of a capsule row to `failed` — swallows its own errors
  /// (network down, etc.) so it never throws from a catch/cleanup path.
  Future<void> _safeMarkFailed(String capsuleId) async {
    try {
      await SupabaseService.updateCapsulePayload(capsuleId: capsuleId, status: 'failed');
    } catch (e) {
      debugPrint('Could not mark capsule $capsuleId failed: $e');
    }
  }

  /// Best-effort: reverse-geocode a drop location and persist the city label
  /// for the Home card title. Swallows all errors (offline / no result).
  Future<void> _setSentCityBestEffort(
    String capsuleId,
    double latitude,
    double longitude,
  ) async {
    try {
      final city = await GeocodingService.cityFor(latitude, longitude);
      if (city == null || city.isEmpty) return;
      await SupabaseService.updateSentCapsuleCity(capsuleId: capsuleId, city: city);
      _bumpCapsulesChanged();
    } catch (e) {
      debugPrint('Could not set city for capsule $capsuleId: $e');
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
        capsuleCreatedAt: capsule.createdAt,
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
      userLatitude = position.latitude;
      userLongitude = position.longitude;

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

      // Accuracy-aware proximity: a consumer GPS fix has a ±accuracy radius, so
      // standing exactly on the spot commonly reads e.g. "16 m". Treat the
      // closest the device could plausibly be (meters − accuracy) against the
      // threshold, capping the accuracy bonus so a poor fix can't unlock from
      // far away.
      final threshold = SystemConfig.instance.unlockProximityMeters;
      final accuracyBonus =
          position.accuracy.clamp(0.0, AppConstants.maxGpsAccuracyBonusMeters);
      final withinProximity =
          meters <= threshold || (meters - accuracyBonus) <= threshold;

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
      await SupabaseService.markReceivedCapsuleUnlocked(
        userId: userId,
        capsuleId: capsule.id,
      );
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
