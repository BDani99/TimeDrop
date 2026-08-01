import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../errors/app_exception.dart';

/// Pure AES-256-GCM encrypt/decrypt envelope primitives. No I/O here — this
/// is the one file the entire E2EE trust boundary depends on, so it stays
/// small and easy to audit.
///
/// Envelope wire format (all multi-byte fields are raw bytes, not text):
///   [1 byte version = 0x01] [12 bytes nonce] [ciphertext, variable] [16 bytes GCM tag]
///
/// The same per-capsule key is used for exactly two envelopes in its
/// lifetime (media blob, metadata JSON) — safe because each encrypt() call
/// generates a fresh random nonce, so nonces are never reused under one key.
class AesGcmEnvelope {
  AesGcmEnvelope._();

  static const int _versionByte = 0x01;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;

  static final _algorithm = AesGcm.with256bits();

  /// Generates a fresh 256-bit key. Call once per capsule; never persist or
  /// transmit the raw bytes to any server.
  static Future<SecretKey> generateKey() => _algorithm.newSecretKey();

  static Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required SecretKey key,
  }) async {
    try {
      final secretBox = await _algorithm.encrypt(plaintext, secretKey: key);
      final nonce = Uint8List.fromList(secretBox.nonce);
      final cipherText = Uint8List.fromList(secretBox.cipherText);
      final mac = Uint8List.fromList(secretBox.mac.bytes);

      if (nonce.length != _nonceLength || mac.length != _tagLength) {
        throw const CryptoException('Unexpected AES-GCM envelope shape.');
      }

      final envelope = BytesBuilder();
      envelope.addByte(_versionByte);
      envelope.add(nonce);
      envelope.add(cipherText);
      envelope.add(mac);
      return envelope.toBytes();
    } on CryptoException {
      rethrow;
    } catch (e) {
      throw CryptoException('Failed to encrypt payload.', cause: e);
    }
  }

  static Future<Uint8List> decrypt({
    required Uint8List envelope,
    required SecretKey key,
  }) async {
    try {
      if (envelope.length < 1 + _nonceLength + _tagLength) {
        throw const CryptoException('Encrypted payload is too short to be valid.');
      }
      final version = envelope[0];
      if (version != _versionByte) {
        throw const CryptoException('Unsupported encryption envelope version.');
      }

      final nonce = envelope.sublist(1, 1 + _nonceLength);
      final tagStart = envelope.length - _tagLength;
      final cipherText = envelope.sublist(1 + _nonceLength, tagStart);
      final mac = envelope.sublist(tagStart);

      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final plaintext = await _algorithm.decrypt(secretBox, secretKey: key);
      return Uint8List.fromList(plaintext);
    } on CryptoException {
      rethrow;
    } catch (e) {
      throw CryptoException(
        'Failed to decrypt payload — the key or link may be corrupted.',
        cause: e,
      );
    }
  }

  /// URL-fragment-safe key encoding: base64url without padding (32 raw
  /// bytes -> 43 chars). Safe to place after `#` in a share link.
  static Future<String> keyToUrlSafeString(SecretKey key) async {
    final bytes = await key.extractBytes();
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Expected raw key length. AES-256 means exactly 32 bytes.
  static const int _keyLength = 32;

  static SecretKey keyFromUrlSafeString(String encoded) {
    final List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(encoded));
    } catch (e) {
      throw CryptoException('The share link key is malformed.', cause: e);
    }

    // Checked here rather than left to decrypt(): a truncated link produces a
    // short key, and without this the failure surfaces much later as "the key
    // or link may be corrupted" — which hides the actual cause (an incomplete
    // link) from both the user and anyone debugging it.
    if (bytes.length != _keyLength) {
      throw CryptoException(
        'This share link looks incomplete — copy the whole link and try again.',
        cause: 'Expected a $_keyLength-byte key, got ${bytes.length}.',
      );
    }
    return SecretKey(bytes);
  }
}
