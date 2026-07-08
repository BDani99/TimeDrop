import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide StorageException;

import '../core/constants/supabase_constants.dart';
import '../core/errors/app_exception.dart';
import 'supabase_service.dart';

/// Upload/download of encrypted media blobs to/from the private
/// `capsule-media` Storage bucket. Callers must pass already-encrypted
/// bytes — this service never sees plaintext.
class StorageService {
  StorageService._();

  static StorageFileApi get _bucket =>
      SupabaseService.client.storage.from(SupabaseConstants.capsuleMediaBucket);

  static Future<void> uploadEncrypted({
    required String storagePath,
    required Uint8List encryptedBytes,
  }) async {
    try {
      await _bucket.uploadBinary(
        storagePath,
        encryptedBytes,
        fileOptions: const FileOptions(
          contentType: 'application/octet-stream',
          upsert: false,
        ),
      );
    } catch (e) {
      throw StorageException('Could not upload the memory.', cause: e);
    }
  }

  static Future<Uint8List> downloadEncrypted(String storagePath) async {
    try {
      return await _bucket.download(storagePath);
    } catch (e) {
      throw StorageException('Could not download the memory.', cause: e);
    }
  }
}
