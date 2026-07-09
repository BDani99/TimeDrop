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

  /// Ready to physically go unlock: time has passed, not yet viewed, and we
  /// hold the key.
  List<ReceivedCapsuleModel> get ready => receivedCapsules
      .where((c) => !c.isViewed && c.isUnlockTimeReached && c.hasKey)
      .toList();

  /// Still time-locked (or missing the key) and not yet viewed.
  List<ReceivedCapsuleModel> get waiting => receivedCapsules
      .where((c) => !c.isViewed && !(c.isUnlockTimeReached && c.hasKey))
      .toList();

  /// Already opened at least once — replayable from cache.
  List<ReceivedCapsuleModel> get unlocked =>
      receivedCapsules.where((c) => c.isViewed).toList();

  int get unlockedCount => unlocked.length;

  int get cityCount => unlocked
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

  Future<void> load(String userId) async {
    isLoading = true;
    notifyListeners();
    try {
      receivedCapsules = await SupabaseService.fetchReceivedCapsules(userId);
      notifyListeners();
      // Lazily fill missing city labels (best-effort, non-blocking).
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

    await SupabaseService.upsertReceivedCapsule(
      userId: userId,
      capsuleId: capsule.id,
      shareId: capsule.shareId,
      unlockTime: capsule.unlockTime,
      latitude: capsule.latitude,
      longitude: capsule.longitude,
      encryptionKey: link?.encryptionKey,
      fromName: link?.fromName,
    );
    await load(userId);
    return link;
  }

  /// Re-opens an already-viewed capsule for replay — cache-first (offline),
  /// falling back to download + decrypt (e.g. after a reinstall), and
  /// re-caching so the next replay is offline.
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

    final key = item.encryptionKey;
    if (key == null) {
      throw const CapsuleException('The full link is needed to open this memory.');
    }
    final capsule = await SupabaseService.fetchCapsuleByShareId(item.shareId);
    if (capsule?.encryptedPayload == null) {
      throw const CapsuleException('This memory is not unlocked yet.');
    }
    final metadata = await CryptoService.decryptMetadata(
      encryptedPayloadBase64: capsule!.encryptedPayload!,
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
