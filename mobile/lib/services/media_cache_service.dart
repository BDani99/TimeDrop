import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Decrypted capsule content held on disk after first view, so the Vault can
/// replay a memory offline and show its cover thumbnail without re-fetching /
/// re-decrypting. Lives in the app-support directory (survives restarts,
/// cleared on uninstall). Keyed by capsuleId.
class MediaCacheService {
  MediaCacheService._();

  static Directory? _root;

  static Future<Directory> _dir(String capsuleId) async {
    _root ??= await getApplicationSupportDirectory();
    final dir = Directory('${_root!.path}/capsules/$capsuleId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<bool> has(String capsuleId) async {
    _root ??= await getApplicationSupportDirectory();
    return File('${_root!.path}/capsules/$capsuleId/video.mp4').exists();
  }

  /// Persists the decrypted content. [note] and [photos] are optional.
  static Future<void> store({
    required String capsuleId,
    required Uint8List video,
    String? note,
    List<Uint8List> photos = const [],
    int? coverPhotoIndex,
  }) async {
    final dir = await _dir(capsuleId);
    await File('${dir.path}/video.mp4').writeAsBytes(video);
    final meta = <String, dynamic>{
      'note': ?note,
      'photoCount': photos.length,
      'coverPhotoIndex': ?coverPhotoIndex,
    };
    await File('${dir.path}/meta.json').writeAsString(jsonEncode(meta));
    for (var i = 0; i < photos.length; i++) {
      await File('${dir.path}/photo_$i.jpg').writeAsBytes(photos[i]);
    }
  }

  static Future<CachedCapsule?> get(String capsuleId) async {
    if (!await has(capsuleId)) return null;
    final dir = await _dir(capsuleId);
    final video = await File('${dir.path}/video.mp4').readAsBytes();
    Map<String, dynamic> meta = const {};
    final metaFile = File('${dir.path}/meta.json');
    if (await metaFile.exists()) {
      meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    }
    final photoCount = meta['photoCount'] as int? ?? 0;
    final photos = <Uint8List>[];
    for (var i = 0; i < photoCount; i++) {
      final f = File('${dir.path}/photo_$i.jpg');
      if (await f.exists()) photos.add(await f.readAsBytes());
    }
    return CachedCapsule(
      video: video,
      note: meta['note'] as String?,
      photos: photos,
      coverPhotoIndex: meta['coverPhotoIndex'] as int?,
    );
  }

  /// Just the cached note text (for a card preview), if any.
  static Future<String?> noteFor(String capsuleId) async {
    _root ??= await getApplicationSupportDirectory();
    final metaFile = File('${_root!.path}/capsules/$capsuleId/meta.json');
    if (!await metaFile.exists()) return null;
    final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    return meta['note'] as String?;
  }

  /// Just the cover photo bytes (for a card thumbnail), if cached.
  static Future<Uint8List?> coverPhoto(String capsuleId) async {
    final dir = await _dir(capsuleId);
    final metaFile = File('${dir.path}/meta.json');
    if (!await metaFile.exists()) return null;
    final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final index = meta['coverPhotoIndex'] as int? ?? 0;
    final f = File('${dir.path}/photo_$index.jpg');
    if (await f.exists()) return f.readAsBytes();
    // Fall back to the first photo if the chosen cover isn't there.
    final first = File('${dir.path}/photo_0.jpg');
    if (await first.exists()) return first.readAsBytes();
    return null;
  }
}

class CachedCapsule {
  const CachedCapsule({
    required this.video,
    required this.photos,
    this.note,
    this.coverPhotoIndex,
  });

  final Uint8List video;
  final String? note;
  final List<Uint8List> photos;
  final int? coverPhotoIndex;
}
