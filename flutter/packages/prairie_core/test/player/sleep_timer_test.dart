import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/player/sleep_timer.dart';

void main() {
  test('labels presets in minutes and hours', () {
    expect(sleepTimerPresets.map(sleepTimerLabel), ['5 min', '15 min', '30 min', '45 min', '1 hour', '2 hours']);
  });

  test('remaining is null once the deadline has passed', () {
    final deadline = DateTime(2026, 1, 1, 22);
    expect(sleepTimerRemaining(deadline, DateTime(2026, 1, 1, 21, 30)), const Duration(minutes: 30));
    expect(sleepTimerRemaining(deadline, deadline), isNull);
    expect(sleepTimerRemaining(deadline, DateTime(2026, 1, 1, 22, 0, 1)), isNull);
  });

  test('countdown rounds up and switches to hours', () {
    expect(formatSleepCountdown(const Duration(milliseconds: 1)), '0:01');
    expect(formatSleepCountdown(const Duration(minutes: 4, seconds: 59, milliseconds: 500)), '5:00');
    expect(formatSleepCountdown(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
