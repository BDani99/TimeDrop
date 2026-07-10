import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Restart-safe queue for background capsule uploads.
///
/// The optimistic-UI flow inserts a `pending` capsule row, then compresses /
/// encrypts / uploads the media in a fire-and-forget task. If the app is
/// killed (or the OS purges the temp recording) mid-upload, that work — and
/// therefore the capsule — would be lost, leaving the row stuck on `pending`
/// forever. This service persists each job to disk and copies its media into
/// app-private storage so the upload can be resumed on the next launch.
///
/// Layout (under the app-support dir):
///   `upload_queue/queue.json`               — manifest: list of [UploadJob]
///   `upload_queue/{capsuleId}/{file}`       — persistent copies of the media
/// The AES key is kept in the OS keystore (not the plaintext manifest).
class UploadQueueService {
  UploadQueueService._();

  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'upload_key_';

  static Directory? _root;

  static Future<Directory> _queueDir() async {
    _root ??= await getApplicationSupportDirectory();
    final dir = Directory('${_root!.path}/upload_queue');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _manifestFile() async =>
      File('${(await _queueDir()).path}/queue.json');

  static Future<List<UploadJob>> _readManifest() async {
    final file = await _manifestFile();
    if (!await file.exists()) return [];
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .map((e) => UploadJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('UploadQueueService: corrupt manifest, resetting: $e');
      return [];
    }
  }

  static Future<void> _writeManifest(List<UploadJob> jobs) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(jobs.map((j) => j.toJson()).toList()));
  }

  /// Copies [mediaPath] + [photoPaths] into app-private storage, persists the
  /// job to the manifest, and stashes [keyUrlSafe] in the keystore. Returns a
  /// job whose paths point at the durable copies (used by the background task
  /// so it reads from storage that survives temp-dir cleanup).
  static Future<UploadJob> enqueue({
    required String capsuleId,
    required String shareId,
    required String keyUrlSafe,
    required String mediaPath,
    required List<String> photoPaths,
    required String mimeType,
    required int durationMs,
    required String creatorId,
    String? note,
    int? coverPhotoIndex,
  }) async {
    final dir = Directory('${(await _queueDir()).path}/$capsuleId');
    if (!await dir.exists()) await dir.create(recursive: true);

    final durableMedia = await _copyInto(dir, mediaPath, 'media');
    final durablePhotos = <String>[];
    for (var i = 0; i < photoPaths.length; i++) {
      durablePhotos.add(await _copyInto(dir, photoPaths[i], 'photo_$i'));
    }

    await _storage.write(key: '$_keyPrefix$capsuleId', value: keyUrlSafe);

    final job = UploadJob(
      capsuleId: capsuleId,
      shareId: shareId,
      mediaPath: durableMedia,
      photoPaths: durablePhotos,
      mimeType: mimeType,
      durationMs: durationMs,
      creatorId: creatorId,
      note: note,
      coverPhotoIndex: coverPhotoIndex,
      attempts: 0,
    );

    final jobs = await _readManifest()
      ..removeWhere((j) => j.capsuleId == capsuleId)
      ..add(job);
    await _writeManifest(jobs);
    return job;
  }

  /// Copies [sourcePath] into [dir] preserving its extension, returns the new
  /// path. Falls back to the source path if the copy fails (e.g. source gone).
  static Future<String> _copyInto(
    Directory dir,
    String sourcePath,
    String baseName,
  ) async {
    final dot = sourcePath.lastIndexOf('.');
    final slash = sourcePath.lastIndexOf(RegExp(r'[/\\]'));
    final ext = (dot > slash && dot != -1) ? sourcePath.substring(dot) : '';
    final dest = '${dir.path}/$baseName$ext';
    try {
      await File(sourcePath).copy(dest);
      return dest;
    } catch (e) {
      debugPrint('UploadQueueService: could not copy $sourcePath: $e');
      return sourcePath;
    }
  }

  /// All jobs awaiting (re)upload, oldest first.
  static Future<List<UploadJob>> pending() => _readManifest();

  /// The AES key stashed for [capsuleId], if still present.
  static Future<String?> keyFor(String capsuleId) =>
      _storage.read(key: '$_keyPrefix$capsuleId');

  /// Persists an incremented attempt counter for [capsuleId].
  static Future<void> markAttempt(String capsuleId) async {
    final jobs = await _readManifest();
    final idx = jobs.indexWhere((j) => j.capsuleId == capsuleId);
    if (idx == -1) return;
    jobs[idx] = jobs[idx].copyWith(attempts: jobs[idx].attempts + 1);
    await _writeManifest(jobs);
  }

  /// Removes the job (manifest entry, media copies, and stored key). Called on
  /// successful upload or when a job is abandoned as permanently failed.
  static Future<void> remove(String capsuleId) async {
    final jobs = await _readManifest()
      ..removeWhere((j) => j.capsuleId == capsuleId);
    await _writeManifest(jobs);
    await _storage.delete(key: '$_keyPrefix$capsuleId');
    try {
      final dir = Directory('${(await _queueDir()).path}/$capsuleId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('UploadQueueService: could not delete media for $capsuleId: $e');
    }
  }
}

/// A persisted background-upload job. Paths point at durable app-private
/// copies of the media (see [UploadQueueService.enqueue]).
class UploadJob {
  const UploadJob({
    required this.capsuleId,
    required this.shareId,
    required this.mediaPath,
    required this.photoPaths,
    required this.mimeType,
    required this.durationMs,
    required this.creatorId,
    required this.attempts,
    this.note,
    this.coverPhotoIndex,
  });

  final String capsuleId;
  final String shareId;
  final String mediaPath;
  final List<String> photoPaths;
  final String mimeType;
  final int durationMs;
  final String creatorId;
  final String? note;
  final int? coverPhotoIndex;
  final int attempts;

  UploadJob copyWith({int? attempts}) => UploadJob(
        capsuleId: capsuleId,
        shareId: shareId,
        mediaPath: mediaPath,
        photoPaths: photoPaths,
        mimeType: mimeType,
        durationMs: durationMs,
        creatorId: creatorId,
        note: note,
        coverPhotoIndex: coverPhotoIndex,
        attempts: attempts ?? this.attempts,
      );

  Map<String, dynamic> toJson() => {
        'capsuleId': capsuleId,
        'shareId': shareId,
        'mediaPath': mediaPath,
        'photoPaths': photoPaths,
        'mimeType': mimeType,
        'durationMs': durationMs,
        'creatorId': creatorId,
        'note': ?note,
        'coverPhotoIndex': ?coverPhotoIndex,
        'attempts': attempts,
      };

  factory UploadJob.fromJson(Map<String, dynamic> json) => UploadJob(
        capsuleId: json['capsuleId'] as String,
        shareId: json['shareId'] as String? ?? '',
        mediaPath: json['mediaPath'] as String,
        photoPaths: (json['photoPaths'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        mimeType: json['mimeType'] as String,
        durationMs: json['durationMs'] as int? ?? 0,
        creatorId: json['creatorId'] as String,
        note: json['note'] as String?,
        coverPhotoIndex: json['coverPhotoIndex'] as int?,
        attempts: json['attempts'] as int? ?? 0,
      );
}
