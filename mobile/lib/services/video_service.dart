import 'package:video_compress/video_compress.dart';

/// Wraps `video_compress` so the capture pipeline can shrink a recorded
/// video before encryption/upload — keeping Supabase Storage cost and
/// upload size down. Compression is best-effort: any failure (unsupported
/// device, plugin error) falls back to the original file so a recording is
/// never lost.
class VideoService {
  VideoService._();

  /// Compresses the video at [inputPath] and returns the compressed file's
  /// path, or [inputPath] unchanged if compression isn't available/fails.
  static Future<String> compress(String inputPath) async {
    try {
      final info = await VideoCompress.compressVideo(
        inputPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      final compressedPath = info?.path;
      if (compressedPath != null && compressedPath.isNotEmpty) {
        return compressedPath;
      }
      return inputPath;
    } catch (_) {
      return inputPath;
    }
  }
}
