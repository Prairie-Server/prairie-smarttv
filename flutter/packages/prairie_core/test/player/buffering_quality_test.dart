import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  final t0 = DateTime(2026, 11, 3, 20);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  /// Feeds a stall from [from] to [to] (seconds), one sample a second, and
  /// returns whether any sample asked to step down.
  bool stall(BufferingStallTracker tracker, int from, int to) {
    var triggered = false;
    for (var s = from; s < to; s++) {
      triggered = tracker.update(stalled: true, now: at(s)) || triggered;
    }
    return tracker.update(stalled: false, now: at(to)) || triggered;
  }

  group('BufferingStallTracker', () {
    test('does nothing before a plan has played', () {
      final tracker = BufferingStallTracker();
      expect(stall(tracker, 0, 3), isFalse);
      expect(stall(tracker, 10, 13), isFalse);
    });

    test('two counted stalls within two minutes step down', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      expect(stall(tracker, 30, 32), isFalse);
      expect(tracker.countedStalls, 1);
      expect(stall(tracker, 60, 62), isTrue);
      expect(tracker.countedStalls, 0);
    });

    test('stalls in the startup grace or under a second are not counted', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      expect(stall(tracker, 2, 5), isFalse); // startup
      expect(tracker.countedStalls, 0);
      tracker.update(stalled: true, now: at(30));
      tracker.update(stalled: false, now: at(30).add(const Duration(milliseconds: 900)));
      expect(tracker.countedStalls, 0);
    });

    test('stalls further apart than the window do not add up', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      expect(stall(tracker, 20, 22), isFalse);
      expect(stall(tracker, 200, 202), isFalse);
      expect(tracker.countedStalls, 1);
    });

    test('one six-second stall steps down while it lasts, once', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      var fired = 0;
      for (var s = 30; s < 45; s++) {
        if (tracker.update(stalled: true, now: at(s))) fired++;
      }
      expect(fired, 1);
      expect(tracker.update(stalled: false, now: at(45)), isFalse);
      expect(tracker.countedStalls, 0);
    });

    test('a restore holds off stepping down for five minutes', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      tracker.suppress(at(20));
      expect(stall(tracker, 30, 32), isFalse);
      expect(stall(tracker, 60, 62), isFalse);
      expect(stall(tracker, 400, 402), isFalse);
      expect(stall(tracker, 420, 422), isTrue);
    });

    test('a new plan starts the history over', () {
      final tracker = BufferingStallTracker()..planStarted(at(0));
      expect(stall(tracker, 30, 32), isFalse);
      tracker.planStarted(at(40));
      expect(tracker.countedStalls, 0);
      expect(stall(tracker, 45, 47), isFalse); // inside the new plan's grace
      expect(stall(tracker, 60, 62), isFalse);
      expect(stall(tracker, 80, 82), isTrue);
    });
  });

  group('bufferingStepDownRung', () {
    final offered = {for (final r in fallbackQualityLadder) r.id};

    test('steps from the source height to the best rung below it', () {
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 2160, offeredIds: offered)?.id, '1080p-high');
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 1080, offeredIds: offered)?.id, '720p-high');
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 720, offeredIds: offered)?.id, '480p');
    });

    test('only offers rungs the quality menu has', () {
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 1080, offeredIds: {'720p', '480p'})?.id, '720p');
    });

    test('nothing lower, or an unknown height, gives null', () {
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 420, offeredIds: offered), isNull);
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 0, offeredIds: offered), isNull);
      expect(bufferingStepDownRung(fallbackQualityLadder, currentHeight: 1080, offeredIds: const {}), isNull);
    });
  });
}
