import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedrop_mobile/core/crypto/aes_gcm_envelope.dart';
import 'package:timedrop_mobile/core/errors/app_exception.dart';
import 'package:timedrop_mobile/models/drop_state_model.dart';

/// Regression tests for the pre-release audit fixes. Each one covers a defect
/// that was actually present, not a hypothetical.
void main() {
  group('AesGcmEnvelope.keyFromUrlSafeString', () {
    String encodeBytes(int length) =>
        base64Url.encode(List<int>.filled(length, 7)).replaceAll('=', '');

    test('accepts a correct 32-byte key', () {
      expect(() => AesGcmEnvelope.keyFromUrlSafeString(encodeBytes(32)),
          returnsNormally);
    });

    test('rejects a truncated key instead of failing later at decrypt', () {
      // A share link cut short by a messaging app used to produce a short key
      // and only fail much later with "the key or link may be corrupted".
      expect(
        () => AesGcmEnvelope.keyFromUrlSafeString(encodeBytes(16)),
        throwsA(isA<CryptoException>()),
      );
    });

    test('rejects an over-long key', () {
      expect(
        () => AesGcmEnvelope.keyFromUrlSafeString(encodeBytes(48)),
        throwsA(isA<CryptoException>()),
      );
    });

    test('rejects text that is not base64 at all', () {
      expect(
        () => AesGcmEnvelope.keyFromUrlSafeString('not a key!!'),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('DropState.mergeBalances', () {
    DropState freeState() => DropState(
          freeRemaining: 1,
          subscriptionRemaining: 0,
          purchasedRemaining: 3,
          totalRemaining: 4,
          canCreate: true,
          isReviewer: false,
          subscriptionStatus: 'none',
          nextBucket: 'free',
          maxUnlockTime: DateTime.now().add(const Duration(days: 60)),
        );

    test('clears the horizon cap once the free drop is spent', () {
      // The cap only applies to a free drop. Carrying it over kept the date
      // picker locked to two months for a drop the user had paid for.
      final after = freeState().mergeBalances({
        'free_remaining': 0,
        'subscription_remaining': 0,
        'purchased_remaining': 3,
        'total_remaining': 3,
      });

      expect(after.nextBucket, 'purchased');
      expect(after.maxUnlockTime, isNull);
      expect(after.isNextDropFree, isFalse);
    });

    test('keeps the cap while the next drop is still the free one', () {
      final after = freeState().mergeBalances({
        'free_remaining': 1,
        'subscription_remaining': 0,
        'purchased_remaining': 2,
        'total_remaining': 3,
      });

      expect(after.nextBucket, 'free');
      expect(after.maxUnlockTime, isNotNull);
      expect(after.isNextDropFree, isTrue);
    });

    test('an empty balance cannot create and has no next bucket', () {
      final after = freeState().mergeBalances({
        'free_remaining': 0,
        'subscription_remaining': 0,
        'purchased_remaining': 0,
        'total_remaining': 0,
      });

      expect(after.canCreate, isFalse);
      expect(after.nextBucket, isNull);
      expect(after.maxUnlockTime, isNull);
    });

    test('a reviewer can always create and is never horizon-capped', () {
      final reviewer = DropState(
        freeRemaining: 0,
        subscriptionRemaining: 0,
        purchasedRemaining: 0,
        totalRemaining: 0,
        canCreate: true,
        isReviewer: true,
        subscriptionStatus: 'none',
        nextBucket: 'reviewer',
      );

      final after = reviewer.mergeBalances({
        'free_remaining': 0,
        'subscription_remaining': 0,
        'purchased_remaining': 0,
        'total_remaining': 0,
      });

      expect(after.canCreate, isTrue);
      expect(after.nextBucket, 'reviewer');
      expect(after.maxUnlockTime, isNull);
      expect(after.isNextDropFree, isFalse);
    });
  });

  group('DropState.unknown', () {
    test('fails open: an unloaded balance never blocks the UI', () {
      // The server enforces the real quota, so an optimistic client costs
      // nothing — whereas a pessimistic one would block a paying user while
      // their balance is still loading.
      expect(const DropState.unknown().canCreate, isTrue);
      expect(const DropState.unknown().maxUnlockTime, isNull);
    });
  });
}
