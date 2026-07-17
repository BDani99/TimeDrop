import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Normalises camera captures before they are attached to a drop.
///
/// Applies EXIF orientation, centre-crops to the on-screen viewport aspect
/// (so the saved JPEG matches the live [BoxFit.cover] preview), and
/// optionally mirrors horizontally.
class PhotoProcessingService {
  PhotoProcessingService._();

  /// Reads [sourcePath], normalises, and writes a new JPEG in temp storage.
  /// Returns the output path (falls back to [sourcePath] if decode fails).
  ///
  /// [viewportAspectWidthOverHeight] should match the preview area width ÷
  /// height (typically [MediaQuery.sizeOf(context).width / height]).
  static Future<String> processCameraCapture({
    required String sourcePath,
    required bool mirror,
    required double viewportAspectWidthOverHeight,
  }) async {
    try {
      final raw = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) return sourcePath;

      var image = img.bakeOrientation(decoded);
      image = _centerCropToAspect(image, viewportAspectWidthOverHeight);
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

  static img.Image _centerCropToAspect(img.Image src, double targetAspect) {
    if (targetAspect <= 0) return src;
    final current = src.width / src.height;

    if (current > targetAspect) {
      final newWidth = (src.height * targetAspect).round();
      final x = (src.width - newWidth) ~/ 2;
      return img.copyCrop(src, x: x, y: 0, width: newWidth, height: src.height);
    }

    final newHeight = (src.width / targetAspect).round();
    final y = (src.height - newHeight) ~/ 2;
    return img.copyCrop(src, x: 0, y: y, width: src.width, height: newHeight);
  }
}
