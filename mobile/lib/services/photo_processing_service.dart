import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Normalises photos before they are attached to a drop.
///
/// Applies EXIF orientation, centre-crops to a target aspect ratio, and
/// optionally mirrors horizontally.
///
/// The target is the **video's** aspect ratio, not the phone screen's. A
/// capsule is one memory: the recipient swipes from the video straight into
/// the photos, and a still that is a different shape from the clip it belongs
/// to reads as a mistake. This used to crop to the viewport, which matched the
/// live preview but not the recording.
class PhotoProcessingService {
  PhotoProcessingService._();

  /// Reads [sourcePath], normalises, and writes a new JPEG in temp storage.
  /// Returns the output path (falls back to [sourcePath] if decode fails) —
  /// an unprocessable photo is still better than no photo.
  ///
  /// [targetAspectWidthOverHeight] is width ÷ height of the capsule's video.
  static Future<String> processCameraCapture({
    required String sourcePath,
    required bool mirror,
    required double targetAspectWidthOverHeight,
  }) async {
    try {
      final raw = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) return sourcePath;

      var image = img.bakeOrientation(decoded);
      image = _centerCropToAspect(image, targetAspectWidthOverHeight);
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
