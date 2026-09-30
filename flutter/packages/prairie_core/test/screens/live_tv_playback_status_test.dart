import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/src/screens/live_tv_player_screen.dart';

void main() {
  LiveTvPlaybackStatus status({
    bool tuning = false,
    bool failed = false,
    bool isPlaying = true,
    bool isBuffering = false,
    bool hasAdvanced = true,
    Duration sinceLastAdvance = Duration.zero,
  }) => liveTvPlaybackStatus(
    tuning: tuning,
    failed: failed,
    isPlaying: isPlaying,
    isBuffering: isBuffering,
    hasAdvanced: hasAdvanced,
    sinceLastAdvance: sinceLastAdvance,
  );

  test('a playing stream whose position has not moved yet is still starting, not live', () {
    expect(status(hasAdvanced: false), LiveTvPlaybackStatus.starting);
  });

  test('an advancing stream is live', () {
    expect(status(sinceLastAdvance: const Duration(seconds: 1)), LiveTvPlaybackStatus.live);
  });

  test('a stream that stops advancing reads as buffering', () {
    expect(status(sinceLastAdvance: liveTvStallThreshold + const Duration(milliseconds: 1)), LiveTvPlaybackStatus.buffering);
    expect(status(isBuffering: true), LiveTvPlaybackStatus.buffering);
  });

  test('pause, tuning and failure take precedence over picture state', () {
    expect(status(isPlaying: false, sinceLastAdvance: const Duration(minutes: 1)), LiveTvPlaybackStatus.paused);
    expect(status(tuning: true, isPlaying: false), LiveTvPlaybackStatus.tuning);
    expect(status(failed: true, tuning: true), LiveTvPlaybackStatus.failed);
  });
}
