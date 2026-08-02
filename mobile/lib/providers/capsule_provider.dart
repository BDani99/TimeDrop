import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

  /// Guards against concurrent GPS events racing mid-decrypt. Without this,
  /// a second position update can [notifyListeners] while [radarPhase] is
  /// already [RadarPhase.unlocked] but [decryptedMediaBytes] is still null —
  /// the Radar UI then locks `_hasUnlocked` and never navigates.
  bool _unlockInFlight = false;
  String? unlockError;

  /// True while proximity has been met and decrypt/download is in flight.
  bool get isUnlocking => _unlockInFlight && radarPhase != RadarPhase.unlocked;

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
    bool allowCodeUnlock = false,
  }) async {
    isCreating = true;
    notifyListeners();

    // Tracks whether we successfully inserted a 'pending' DB row so we can
    // clean it up if anything later in this function fails before _runUpload
    // is scheduled. Without this guard, a failed incrementFreeDropsUsed() or
    // enqueue() would leave an orphaned 'pending' row stuck forever.
    String? insertedCapsuleId;

    // Post-debit balances returned by the reserve RPC, handed back to the
    // caller so the UI can update without a second round trip.
    Map<String, dynamic>? lastReserveResult;

    try {
      final keyUrlSafe = await CryptoService.generateKeyUrlSafe();

      String? shareId;
      String? capsuleId;
      var attempts = 0;
      while (capsuleId == null && attempts < AppConstants.shareIdMaxRetries) {
        final candidate = CryptoService.generateShareId();
        try {
          // Inserts the row AND debits a drop in one transaction. A quota
          // refusal throws DropQuotaException and leaves nothing behind; a
          // share_id collision rolls the debit back with the row, so the retry
          // below never costs the user a drop.
          lastReserveResult = await SupabaseService.createPendingCapsule(
            shareId: candidate,
            latitude: latitude,
            longitude: longitude,
            unlockTime: unlockTime,
            // Only when the sender asked for it. This is the one place the
            // key can reach the server, and it is a per-drop decision.
            codeUnlockKey: allowCodeUnlock ? keyUrlSafe : null,
          );
          capsuleId = lastReserveResult['capsule_id'] as String;
          shareId = candidate;
          insertedCapsuleId = capsuleId; // row now exists; must clean up on failure
        } on PostgrestException catch (e) {
          attempts++;
          if (e.code != '23505' || attempts >= AppConstants.shareIdMaxRetries) {
            throw CapsuleException('Could not save your capsule.', cause: e);
          }
        }
      }

      if (capsuleId == null || shareId == null) {
        throw const CapsuleException('Could not generate a unique share code. Please try again.');
      }

      _uploadStates[capsuleId] = CapsuleUploadState.uploading;

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
        insertedCapsuleId = null; // cleanup done, don't double-mark in outer catch
        throw CapsuleException(
          'The recording file could not be saved for upload. '
          'Please try recording again.',
          cause: e,
        );
      }

      // Upload scheduled — row is now the queue's responsibility.
      insertedCapsuleId = null;
      unawaited(_runUpload(job, keyUrlSafe));
      unawaited(_setSentCityBestEffort(capsuleId, latitude, longitude));

      return CapsuleShareInfo(
        shareId: shareId,
        encryptionKey: keyUrlSafe,
        balances: lastReserveResult,
      );
    } catch (e) {
      // Any failure after the DB row was inserted but before _runUpload was
      // scheduled leaves an orphaned 'pending' row. Mark it failed so the
      // Home card shows a retry option instead of spinning forever.
      final id = insertedCapsuleId;
      if (id != null) {
        _uploadStates[id] = CapsuleUploadState.failed;
        await _safeMarkFailed(id);
      }
      rethrow;
    } finally {
      isCreating = false;
      _bumpCapsulesChanged();
    }
  }

  /// Cross-checks 'pending' capsule DB rows against the local upload queue.
  /// Any row that is 'pending' but has NO queue entry (orphaned — e.g. from a
  /// previous code version, a failed enqueue, or a device reinstall) and is
  /// older than [AppConstants.stuckPendingThreshold] is marked 'failed' so
  /// the Home card shows a retry prompt instead of spinning forever.
  ///
  /// Call once at app start alongside [resumePendingUploads].
  Future<void> reconcileStuckCapsules(String creatorId) async {
    try {
      final pendingInDb = await SupabaseService.fetchPendingCapsules(creatorId);
      if (pendingInDb.isEmpty) return;

      final queuedIds = (await UploadQueueService.pending())
          .map((j) => j.capsuleId)
          .toSet();

      final now = DateTime.now();
      for (final capsule in pendingInDb) {
        // Skip capsules that are actively being uploaded right now.
        if (_uploadStates[capsule.id] == CapsuleUploadState.uploading) continue;
        // Skip if the queue knows about it — resumePendingUploads() handles it.
        if (queuedIds.contains(capsule.id)) continue;
        // Give brand-new capsules a grace period before declaring them stuck.
        final age = now.difference(capsule.createdAt);
        if (age < AppConstants.stuckPendingThreshold) continue;

        debugPrint('CapsuleProvider: reconciling orphaned pending capsule ${capsule.id}');
        _uploadStates[capsule.id] = CapsuleUploadState.failed;
        await _safeMarkFailed(capsule.id);
      }
      _bumpCapsulesChanged();
    } catch (e) {
      debugPrint('CapsuleProvider: reconcileStuckCapsules failed: $e');
    }
  }

  /// Re-drives every persisted upload job left over from a previous session
  /// (app was killed mid-upload). Call once at app start, after the provider
  /// and Supabase session exist.
  ///
  /// Jobs are abandoned as `failed` when:
  /// - The AES key or media file is missing (OS cleaned them up).
  /// - The job has already been attempted [AppConstants.uploadMaxAttempts] times
  ///   (prevents an unrecoverable job from retrying forever on every launch).
  ///
  /// Jobs that already have a saved [UploadJob.encryptedPayload] skip the
  /// compress → encrypt → upload phase and retry only the DB write.
  Future<void> resumePendingUploads() async {
    final jobs = await UploadQueueService.pending();
    for (final job in jobs) {
      // If the payload is already saved we only need network for the DB write,
      // so the media file check is irrelevant — skip the exhaustion guard only
      // when upload already succeeded.
      final payloadReady = job.encryptedPayload != null;

      if (!payloadReady && job.attempts >= AppConstants.uploadMaxAttempts) {
        debugPrint('UploadQueue: abandoning ${job.capsuleId} after ${job.attempts} attempts');
        _uploadStates[job.capsuleId] = CapsuleUploadState.failed;
        await _safeMarkFailed(job.capsuleId);
        await UploadQueueService.remove(job.capsuleId);
        continue;
      }

      final key = await UploadQueueService.keyFor(job.capsuleId);
      final mediaExists = payloadReady || await File(job.mediaPath).exists();

      if (key == null || !mediaExists) {
        _uploadStates[job.capsuleId] = CapsuleUploadState.failed;
        await _safeMarkFailed(job.capsuleId);
        await UploadQueueService.remove(job.capsuleId);
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

  /// Gives up on a failed upload for good: deletes the reserved capsule row and
  /// drops the queued job, its durable media copies and its stashed AES key —
  /// so the share link dies with it and nothing is retried on the next launch.
  ///
  /// Returns the post-refund drop balances so the caller can update the UI.
  ///
  /// The DB row goes first: if that call fails the local job is left intact, so
  /// the card still offers a retry instead of becoming unrecoverable.
  Future<Map<String, dynamic>> discardUpload(String capsuleId) async {
    final balances = await SupabaseService.discardCapsule(capsuleId);
    await UploadQueueService.remove(capsuleId);
    await UploadQueueService.forgetKey(capsuleId);
    _uploadStates.remove(capsuleId);
    _bumpCapsulesChanged();
    return balances;
  }

  /// Runs (or re-runs) the compress → encrypt → upload → finalize pipeline for
  /// a persisted [job].
  ///
  /// **Two-phase design** that survives partial failures without re-uploading:
  ///   1. Compress → encrypt → upload (covered by [AppConstants.uploadTimeout]).
  ///      On success the payload is saved to the queue manifest immediately,
  ///      so if the next step fails the retry skips straight to step 2.
  ///   2. DB row update to 'ready' (separate 30-second timeout).
  ///      If this fails, the job stays in the queue with the saved payload,
  ///      and the next launch only retries the cheap DB write.
  ///
  /// Every network call is bounded by an explicit timeout so no code path can
  /// leave the capsule stuck on 'pending' forever.
  Future<void> _runUpload(UploadJob job, String keyUrlSafe) async {
    await UploadQueueService.markAttempt(job.capsuleId);
    try {
      final String encryptedPayload;
      final List<String> mediaPaths;

      if (job.encryptedPayload != null) {
        // A prior attempt already succeeded at the upload phase — the payload
        // was persisted to the manifest. Skip straight to the DB write.
        encryptedPayload = job.encryptedPayload!;
        mediaPaths = job.mediaPaths ?? const [];
        debugPrint('UploadQueue: skipping re-upload for ${job.capsuleId} — using saved payload');
      } else {
        // Verify the durable media copy exists before starting the heavy pipeline.
        final mediaFile = File(job.mediaPath);
        if (!await mediaFile.exists()) {
          throw StateError(
            'Media file missing at "${job.mediaPath}". '
            'The recording was lost before the upload could start.',
          );
        }

        final result = await () async {
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
        encryptedPayload = result.payload;
        mediaPaths = result.mediaPaths;

        // Persist the payload BEFORE attempting the DB write. If the app dies
        // or the network drops here, the next launch can skip the upload.
        await UploadQueueService.savePayload(
          job.capsuleId,
          encryptedPayload,
          mediaPaths,
        );
      }

      // DB write has its own timeout — a hung Supabase connection after a
      // successful upload was the primary cause of capsules stuck on 'pending'.
      await SupabaseService.updateCapsulePayload(
        capsuleId: job.capsuleId,
        encryptedPayload: encryptedPayload,
        mediaPaths: mediaPaths,
        status: 'ready',
      ).timeout(AppConstants.dbCallTimeout);

      _uploadStates[job.capsuleId] = CapsuleUploadState.ready;
      await UploadQueueService.remove(job.capsuleId);
    } catch (e, st) {
      _uploadStates[job.capsuleId] = CapsuleUploadState.failed;
      debugPrint('Capsule background upload failed (${job.capsuleId}): $e\n$st');
      // The job stays in the queue so the user (or the next launch) can retry.
      await _safeMarkFailed(job.capsuleId);
    } finally {
      _bumpCapsulesChanged();
    }
  }

  /// Best-effort flip of a capsule row to `failed` — swallows its own errors
  /// (network down, etc.) so it never throws from a catch/cleanup path.
  /// Bounded by [AppConstants.dbCallTimeout] so it cannot hang indefinitely.
  Future<void> _safeMarkFailed(String capsuleId) async {
    try {
      await SupabaseService.updateCapsulePayload(capsuleId: capsuleId, status: 'failed')
          .timeout(AppConstants.dbCallTimeout);
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
    _unlockInFlight = false;
    unlockError = null;
    decryptedMediaBytes = null;
    decryptedMetadata = null;
    decryptedNote = null;
    decryptedPhotos = const [];
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
      // Already unlocked (or decrypt running) — still refresh distance for the
      // UI, but never re-enter the unlock path.
      if (_unlockInFlight || radarPhase == RadarPhase.unlocked) {
        distanceMeters = GeolocationService.distanceInMeters(
          startLat: position.latitude,
          startLng: position.longitude,
          endLat: capsule.latitude,
          endLng: capsule.longitude,
        );
        userLatitude = position.latitude;
        userLongitude = position.longitude;
        notifyListeners();
        return;
      }

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
        // Decrypt FIRST, flip phase ONLY after media is ready. Flipping early
        // let concurrent GPS events notifyListeners with null bytes and stuck
        // the Radar on "The moment is yours" forever.
        _unlockInFlight = true;
        unlockError = null;
        notifyListeners();
        try {
          await _decryptActiveCapsule();
          if (decryptedMediaBytes != null && decryptedMetadata != null) {
            radarPhase = RadarPhase.unlocked;
            stopWatchingPosition();
          } else {
            unlockError = 'This memory could not be opened.';
            _unlockInFlight = false;
          }
        } catch (e) {
          unlockError = e.toString();
          _unlockInFlight = false;
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
    if (capsule?.encryptedPayload == null || key == null) {
      throw const CapsuleException('This memory is not ready to open yet.');
    }

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
  const CapsuleShareInfo({
    required this.shareId,
    required this.encryptionKey,
    this.balances,
  });

  final String shareId;
  final String encryptionKey;

  /// Post-debit drop balances straight from the reserve RPC, so the caller can
  /// update [DropBalanceProvider] without re-fetching.
  final Map<String, dynamic>? balances;
}
