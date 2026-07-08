import 'package:flutter/foundation.dart';

import '../core/errors/app_exception.dart';
import '../core/utils/share_link_parser.dart';
import '../models/received_capsule_model.dart';
import '../services/crypto_service.dart';
import '../services/supabase_service.dart';

/// Owns the recipient-side "Gallery": the list of every capsule a user has
/// resolved as a recipient (regardless of unlock status), plus manual
/// code/link entry and re-watching an already-unlocked memory without
/// requiring a fresh GPS proximity check.
class GalleryProvider extends ChangeNotifier {
  bool isLoading = false;
  List<ReceivedCapsuleModel> receivedCapsules = const [];

  List<ReceivedCapsuleModel> get waiting =>
      receivedCapsules.where((c) => !c.isViewed).toList();
  List<ReceivedCapsuleModel> get unlocked =>
      receivedCapsules.where((c) => c.isViewed).toList();

  Future<void> load(String userId) async {
    isLoading = true;
    notifyListeners();
    try {
      receivedCapsules = await SupabaseService.fetchReceivedCapsules(userId);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Resolves manually-typed input — either a full share link (has a
  /// decryption key) or a bare 6-character code (no key, since the key
  /// lives only in the link's hash fragment). Either way the capsule is
  /// tracked into the gallery; a full link is additionally returned so the
  /// caller can navigate straight to the Radar flow.
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
    );
    await load(userId);
    return link;
  }

  /// Re-decrypts an already-viewed capsule for replay from the Gallery —
  /// no GPS proximity check needed since it was already unlocked once.
  Future<(Uint8List mediaBytes, String mimeType)> reopen(ReceivedCapsuleModel item) async {
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
    final mediaBytes = await CryptoService.decryptMedia(
      metadata: metadata,
      encryptionKeyUrlSafe: key,
    );
    return (mediaBytes, metadata.mimeType);
  }
}
