import 'package:flutter_test/flutter_test.dart';
import 'package:timedrop_mobile/core/config/system_config.dart';
import 'package:timedrop_mobile/core/constants/app_constants.dart';
import 'package:timedrop_mobile/core/utils/share_link_parser.dart';
import 'package:timedrop_mobile/ui/screens/unlock_sequence_screen.dart';

/// Covers the three places where the rebuilt recipient flow can fail silently:
/// a deep link that lost its fragment, a navigation mode that flickers at the
/// threshold, and an unlock sequence whose beats drift out of order.
void main() {
  group('ShareLinkParser.parseParts', () {
    test('a complete link still parses into a usable ShareLinkModel', () {
      final key = 'A' * 43;
      final result = ShareLinkParser.parseParts(
        '${AppConstants.shareBaseUrl}/c/ABC123?from=Dani#$key',
      );

      expect(result, isA<ShareLinkModel>());
      final link = result as ShareLinkModel;
      expect(link.shareId, 'ABC123');
      expect(link.encryptionKey, key);
      expect(link.fromName, 'Dani');
    });

    test(
      'a link stripped of its fragment reports the share id instead of null',
      () {
        // Some Android launchers hand over an App Link without the `#…` part.
        // Returning null here is what used to make the drop vanish on tap.
        final result = ShareLinkParser.parseParts(
          '${AppConstants.shareBaseUrl}/c/ABC123',
        );

        expect(result, isA<IncompleteShareLink>());
        expect((result as IncompleteShareLink).shareId, 'ABC123');
      },
    );

    test('a query-string sender name survives a missing key', () {
      final result = ShareLinkParser.parseParts(
        '${AppConstants.shareBaseUrl}/c/ABC123?from=Dani',
      );

      expect(result, isA<IncompleteShareLink>());
      expect((result as IncompleteShareLink).fromName, 'Dani');
    });

    test('text that is not a share link at all is still rejected', () {
      expect(ShareLinkParser.parseParts('hello there'), isNull);
      expect(ShareLinkParser.parseParts(''), isNull);
    });
  });

  group('Macro/micro switch hysteresis', () {
    tearDown(() {
      SystemConfig.instance.radarSwitchMeters = AppConstants.radarSwitchMeters;
    });

    test('the map only returns at a greater distance than the radar takes over',
        () {
      final config = SystemConfig.instance;

      // Without the gap, a GPS fix bouncing across the threshold would swap
      // the entire screen back and forth every few seconds.
      expect(config.mapReturnMeters, greaterThan(config.radarSwitchMeters));
    });

    test('the dead band is wide enough to absorb ordinary GPS jitter', () {
      final config = SystemConfig.instance;
      final band = config.mapReturnMeters - config.radarSwitchMeters;

      expect(band, greaterThanOrEqualTo(10));
    });

    test('a server-tuned switch distance keeps its hysteresis', () {
      SystemConfig.instance.apply(radarSwitchMeters: 80);

      expect(SystemConfig.instance.radarSwitchMeters, 80);
      expect(SystemConfig.instance.mapReturnMeters, greaterThan(80));
    });

    test('a nonsensical server value is ignored rather than applied', () {
      SystemConfig.instance.apply(radarSwitchMeters: 0);

      expect(
        SystemConfig.instance.radarSwitchMeters,
        AppConstants.radarSwitchMeters,
      );
    });
  });

  group('UnlockTimeline', () {
    test('every beat happens in the order the sequence is written', () {
      final beats = UnlockTimeline.orderedBeats;
      for (var i = 1; i < beats.length; i++) {
        expect(
          beats[i],
          greaterThanOrEqualTo(beats[i - 1]),
          reason: 'beat $i (${beats[i]} ms) must not precede its predecessor',
        );
      }
    });

    test('the black intro is over before the capsule appears', () {
      expect(
        UnlockTimeline.introOutEndMs,
        lessThanOrEqualTo(UnlockTimeline.capsuleStartMs),
      );
    });

    test('the capsule cracks with nothing else on screen', () {
      // The whole point of the reordering: the crack is not sharing the frame
      // with text that arrived early.
      expect(
        UnlockTimeline.textStartMs,
        greaterThan(UnlockTimeline.crackEndMs),
      );
      expect(
        UnlockTimeline.capsuleEndMs,
        lessThanOrEqualTo(UnlockTimeline.crackStartMs),
      );
    });

    test('the lines are fully readable before the crossfade begins', () {
      expect(
        UnlockTimeline.textEndMs,
        lessThan(UnlockTimeline.fadeOutStartMs),
      );
    });

    test('the crossfade finishes exactly when the controller does', () {
      expect(UnlockTimeline.fadeOutStartMs, lessThan(UnlockTimeline.totalMs));
      expect(UnlockTimeline.at(UnlockTimeline.totalMs), 1.0);
    });

    test('the sequence stays under the eight seconds it was budgeted', () {
      // It replaced a ~14.6 s two-part ritual; the ceiling is what keeps a
      // future tweak from creeping back toward it.
      expect(UnlockTimeline.totalMs, lessThanOrEqualTo(8000));
    });
  });
}
