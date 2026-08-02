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

    test('the web page\'s timedrop:// handoff URL round-trips', () {
      // The custom scheme exists because a link to the domain the browser is
      // already on cannot re-trigger Universal/App Link handling. If parsing
      // it ever broke, the web page's "Open in TimeDrop" button would appear
      // to work and silently do nothing.
      final key = 'B' * 43;
      final url = ShareLinkParser.buildAppSchemeUrl(
        shareId: 'XYZ789',
        encryptionKey: key,
        fromName: 'Dani',
      );

      final result = ShareLinkParser.parseParts(url);
      expect(result, isA<ShareLinkModel>());
      final link = result as ShareLinkModel;
      expect(link.shareId, 'XYZ789');
      expect(link.encryptionKey, key);
      expect(link.fromName, 'Dani');
    });

    test('a key-less timedrop:// link takes the incomplete branch too', () {
      final result = ShareLinkParser.parseParts('timedrop://c/XYZ789');
      expect(result, isA<IncompleteShareLink>());
      expect((result as IncompleteShareLink).shareId, 'XYZ789');
    });

    test('another app\'s custom scheme is not accepted', () {
      expect(ShareLinkParser.parseParts('notdrop://c/XYZ789#key'), isNull);
      expect(ShareLinkParser.parseParts('timedrop://elsewhere/XYZ789'), isNull);
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
        UnlockTimeline.introEndMs,
        lessThanOrEqualTo(UnlockTimeline.capsuleStartMs),
      );
    });

    test('the three intro lines never overlap', () {
      // They are read one at a time, so each has to be gone before the next
      // one starts — otherwise two lines share the frame and the whole
      // deliberate pacing collapses.
      final starts = UnlockTimeline.lineStartsMs;
      for (var i = 1; i < starts.length; i++) {
        expect(
          starts[i],
          greaterThanOrEqualTo(starts[i - 1] + UnlockTimeline.lineMs),
          reason: 'line $i begins before line ${i - 1} has finished',
        );
      }
    });

    test('the last intro line has time to be read before the screen turns', () {
      final lastStart = UnlockTimeline.lineStartsMs.last;
      expect(
        UnlockTimeline.introEndMs - lastStart,
        greaterThanOrEqualTo(UnlockTimeline.lineFadeMs * 2),
      );
    });

    test('the capsule cracks with nothing else on screen', () {
      // The whole point of the reordering: the crack is not sharing the frame
      // with text that arrived early.
      expect(
        UnlockTimeline.factsStartMs,
        greaterThan(UnlockTimeline.crackEndMs),
      );
      expect(
        UnlockTimeline.capsuleEndMs,
        lessThanOrEqualTo(UnlockTimeline.crackStartMs),
      );
    });

    test('the facts are fully readable before the crossfade begins', () {
      expect(
        UnlockTimeline.factsEndMs,
        lessThan(UnlockTimeline.fadeOutStartMs),
      );
    });

    test('the crossfade finishes exactly when the controller does', () {
      expect(UnlockTimeline.fadeOutStartMs, lessThan(UnlockTimeline.totalMs));
      expect(UnlockTimeline.at(UnlockTimeline.totalMs), 1.0);
    });

    test('the sequence stays inside its twelve-second ceiling', () {
      // It replaced a ~14.6 s ritual that played its two halves in the wrong
      // order. The ceiling is what stops a future tweak creeping back to it.
      expect(UnlockTimeline.totalMs, lessThanOrEqualTo(12000));
    });
  });
}
