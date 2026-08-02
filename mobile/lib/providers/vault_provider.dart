import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/share_link_parser.dart';
import '../models/received_capsule_model.dart';
import '../services/crypto_service.dart';
import '../services/geocoding_service.dart';
import '../services/media_cache_service.dart';
import '../services/supabase_service.dart';

/// Owns the recipient-side "Vault": every capsule the user has resolved as a
/// recipient (regardless of unlock status), manual code/link redemption, and
/// offline-first re-watching of already-opened memories. Keyed by
/// `auth.uid()`, so it works for anonymous accounts too.
class VaultProvider extends ChangeNotifier {
  bool isLoading = false;
  List<ReceivedCapsuleModel> receivedCapsules = const [];

  /// Set by the video player when a memory has just been opened in the field,
  /// read once by the Vault timeline so it can scroll to that card and give it
  /// a brief arrival animation. Cleared as soon as it has been consumed — the
  /// highlight is a one-off welcome, not a persistent selection.
  String? justOpenedCapsuleId;

  void markJustOpened(String? capsuleId) {
    justOpenedCapsuleId = capsuleId;
  }

  /// Returns the pending highlight exactly once.
  String? takeJustOpened() {
    final id = justOpenedCapsuleId;
    justOpenedCapsuleId = null;
    return id;
  }

  /// Ready to physically go unlock: time has passed, not yet viewed, and we
  /// hold the key.
  List<ReceivedCapsuleModel> get ready =>
      receivedCapsules.where((c) => c.isReadyToDiscover).toList();

  /// Still time-locked (or missing the key) and not yet viewed.
  List<ReceivedCapsuleModel> get waiting =>
      receivedCapsules.where((c) => c.isWaiting).toList();

  /// Already opened at least once — replayable from cache.
  List<ReceivedCapsuleModel> get opened =>
      receivedCapsules.where((c) => c.isOpened).toList();

  /// @deprecated Use [opened] — kept as alias for callers not yet migrated.
  List<ReceivedCapsuleModel> get unlocked => opened;

  int get unlockedCount => opened.length;

  int get cityCount => opened
      .map((c) => c.city)
      .where((city) => city != null && city.isNotEmpty)
      .toSet()
      .length;

  /// True when the (anonymous) user has a capsule opening more than 30 days
  /// out — the "high stakes" case where losing the phone loses the memory.
  bool get hasHighStakesCapsule {
    final threshold = DateTime.now().add(const Duration(days: 30));
    return receivedCapsules.any((c) => c.unlockTime.isAfter(threshold));
  }

  Future<void> load(String userId, {bool silent = false}) async {
    if (!silent) {
      isLoading = true;
      notifyListeners();
    }
    try {
      receivedCapsules = await SupabaseService.fetchReceivedCapsules(userId);
      unawaited(_backfillCities(userId));
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _backfillCities(String userId) async {
    var changed = false;
    for (var i = 0; i < receivedCapsules.length; i++) {
      final c = receivedCapsules[i];
      if (c.city != null && c.city!.isNotEmpty) continue;
      final city = await GeocodingService.cityFor(c.latitude, c.longitude);
      if (city == null) continue;
      await SupabaseService.updateReceivedCapsuleCity(
        userId: userId,
        capsuleId: c.capsuleId,
        city: city,
      );
      receivedCapsules[i] = ReceivedCapsuleModel(
        id: c.id,
        capsuleId: c.capsuleId,
        shareId: c.shareId,
        unlockTime: c.unlockTime,
        latitude: c.latitude,
        longitude: c.longitude,
        isViewed: c.isViewed,
        firstSeenAt: c.firstSeenAt,
        encryptionKey: c.encryptionKey,
        fromName: c.fromName,
        city: city,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Resolves manually-typed input — a full share link (has a key) or a bare
  /// 6-char code (no key). Tracks it into the vault; returns the parsed link
  /// (non-null only for a full link) so the caller can jump to the Radar.
  Future<ShareLinkModel?> submitCode(String input, {required String userId}) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const CapsuleException('Enter a code or paste the link you received.');
    }

    final link = ShareLinkParser.tryParse(trimmed);
    final shareId = link?.shareId ?? trimmed.toUpperCase();

    if (link == null && !RegExp(r'^[A-Z0-9]{6}$').hasMatch(shareId)) {
      throw const CapsuleException('Enter the 6-character code or the full link you received.');
    }

    final capsule = await SupabaseService.fetchCapsuleByShareId(shareId);
    if (capsule == null) {
      throw const CapsuleException('No memory found with that code.');
    }

    // A bare code carries no key. It can still open the memory when the
    // sender chose "openable with the code too" — then, and only then, the
    // server hands one back. Otherwise the drop lands in the Vault marked as
    // needing the full link, exactly as before.
    final key = link?.encryptionKey ?? capsule.codeUnlockKey;

    await SupabaseService.upsertReceivedCapsule(
      userId: userId,
      capsuleId: capsule.id,
      shareId: capsule.shareId,
      unlockTime: capsule.unlockTime,
      latitude: capsule.latitude,
      longitude: capsule.longitude,
      encryptionKey: key,
      fromName: link?.fromName,
      capsuleCreatedAt: capsule.createdAt,
    );
    await load(userId);

    // Report a usable link back to the caller so a code-unlockable drop jumps
    // straight to the Radar, the same way a full link does.
    if (link != null) return link;
    if (key == null) return null;
    return ShareLinkModel(shareId: capsule.shareId, encryptionKey: key);
  }

  /// Re-opens an already-viewed capsule for replay — cache-first (offline),
  /// falling back to download + decrypt (e.g. after a reinstall), and
  /// re-caching so the next replay is offline.
  ///
  /// Throws [CapsuleReplayException.needsRadar] when the memory was never
  /// fully retrieved and the caller should route to [RadarScreen] instead.
  Future<DecryptedCapsule> reopen(ReceivedCapsuleModel item) async {
    final cached = await MediaCacheService.get(item.capsuleId);
    if (cached != null) {
      return DecryptedCapsule(
        mediaBytes: cached.video,
        mimeType: 'video/mp4',
        note: cached.note,
        photos: cached.photos,
        coverPhotoIndex: cached.coverPhotoIndex,
      );
    }

    if (!item.hasKey) {
      throw const CapsuleException('The full link is needed to open this memory.');
    }
    if (!item.isUnlockTimeReached) {
      throw CapsuleReplayException.notOpenYet();
    }

    final capsule = await SupabaseService.fetchCapsuleByShareId(item.shareId);
    if (capsule == null) {
      throw const CapsuleException('This memory could not be found.');
    }
    if (capsule.isPending) {
      throw const CapsuleException('This memory is still sealing. Try again in a moment.');
    }
    if (capsule.encryptedPayload == null) {
      // Viewed flag set but payload never landed — send back to discovery.
      throw CapsuleReplayException.needsRadar();
    }

    final key = item.encryptionKey!;
    final metadata = await CryptoService.decryptMetadata(
      encryptedPayloadBase64: capsule.encryptedPayload!,
      encryptionKeyUrlSafe: key,
    );
    final mediaBytes = await CryptoService.decryptBlob(
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
    await MediaCacheService.store(
      capsuleId: item.capsuleId,
      video: mediaBytes,
      note: metadata.note,
      photos: photos,
      coverPhotoIndex: metadata.coverPhotoIndex,
    );
    return DecryptedCapsule(
      mediaBytes: mediaBytes,
      mimeType: metadata.mimeType,
      note: metadata.note,
      photos: photos,
      coverPhotoIndex: metadata.coverPhotoIndex,
    );
  }
}

/// Thrown by [VaultProvider.reopen] when replay cannot proceed and the UI
/// should fall back to the Radar discovery flow.
enum CapsuleReplayReason { needsRadar, notOpenYet }

class CapsuleReplayException implements Exception {
  CapsuleReplayException._(this.reason, this.message);

  final CapsuleReplayReason reason;
  final String message;

  factory CapsuleReplayException.needsRadar() => CapsuleReplayException._(
        CapsuleReplayReason.needsRadar,
        'Find the place again to open this memory.',
      );

  factory CapsuleReplayException.notOpenYet() => CapsuleReplayException._(
        CapsuleReplayReason.notOpenYet,
        'This memory is not open yet.',
      );

  @override
  String toString() => message;
}

/// Fully decrypted capsule content ready for playback (video + optional note
/// + optional photos).
class DecryptedCapsule {
  const DecryptedCapsule({
    required this.mediaBytes,
    required this.mimeType,
    required this.photos,
    this.note,
    this.coverPhotoIndex,
  });

  final Uint8List mediaBytes;
  final String mimeType;
  final List<Uint8List> photos;
  final String? note;
  final int? coverPhotoIndex;
}
