import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Normalises camera captures before they are attached to a drop.
///
/// Applies EXIF orientation (devices differ), centre-crops to a consistent
/// portrait aspect ratio, and optionally mirrors horizontally.
class PhotoProcessingService {
  PhotoProcessingService._();

  /// Portrait 3:4 — close to most phone sensors; prevents ultra-tall frames
  /// (e.g. some OnePlus devices) from being stored as-is.
  static const _aspectW = 3;
  static const _aspectH = 4;

  /// Reads [sourcePath], normalises, and writes a new JPEG in temp storage.
  /// Returns the output path (falls back to [sourcePath] if decode fails).
  static Future<String> processCameraCapture({
    required String sourcePath,
    required bool mirror,
  }) async {
    try {
      final raw = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) return sourcePath;

      var image = img.bakeOrientation(decoded);
      image = _centerCropAspect(image, _aspectW, _aspectH);
      if (mirror) {
        image = img.flipHorizontal(image);
      }

      final outBytes = img.encodeJpg(image, quality: 92);
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/drop_photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(outBytes, flush: true);
      return out.path;
    } catch (_) {
      return sourcePath;
    }
  }

  static img.Image _centerCropAspect(img.Image src, int aspectW, int aspectH) {
    final target = aspectW / aspectH;
    final current = src.width / src.height;

    if (current > target) {
      final newWidth = (src.height * target).round();
      final x = (src.width - newWidth) ~/ 2;
      return img.copyCrop(src, x: x, y: 0, width: newWidth, height: src.height);
    }

    final newHeight = (src.width / target).round();
    final y = (src.height - newHeight) ~/ 2;
    return img.copyCrop(src, x: 0, y: y, width: src.width, height: newHeight);
  }
}
