/// Sleep timer presets in minutes — the same set the Apple player offers.
const sleepTimerPresets = <int>[5, 15, 30, 45, 60, 120];

String sleepTimerLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  return hours == 1 ? '1 hour' : '$hours hours';
}

/// Time left until [deadline], or null once it has passed (the timer fires).
Duration? sleepTimerRemaining(DateTime deadline, DateTime now) {
  final left = deadline.difference(now);
  return left > Duration.zero ? left : null;
}

/// Countdown text for the player chip: `m:ss`, or `h:mm:ss` from an hour up.
/// Rounds up so the chip never shows `0:00` while time is still left.
String formatSleepCountdown(Duration remaining) {
  final total = (remaining.inMilliseconds + 999) ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}
