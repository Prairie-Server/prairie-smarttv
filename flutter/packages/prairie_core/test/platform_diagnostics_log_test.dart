import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('keeps only the newest events, oldest first, timestamped', () {
    final log = DiagnosticsLog(capacity: 3, clock: () => DateTime(2026, 9, 30, 4, 5, 6));
    for (final e in ['a', 'b', 'c', 'd']) {
      log.add(e);
    }
    expect(log.events, ['04:05:06 b', '04:05:06 c', '04:05:06 d']);
  });

  test('a v3 plan becomes a one-line summary for the stats overlay', () {
    final session = PlaybackSessionResponse.fromJson({
      'session_id': 's',
      'playback_plan': {
        'delivery': 'server_remux_progressive',
        'decision_reason': 'audio_adaptation',
        'requested_media_file_id': '14673',
        'stream': {'protocol': 'http_progressive', 'container': 'mp4', 'url': '/api/v2/stream/s?st=x'},
        'effective_recipe': {'video_codec': 'hevc', 'width': 3840, 'height': 1600, 'dynamic_range': 'hdr10', 'audio_codec': 'aac', 'audio_channels': 2},
      },
    });
    expect(
      session.planSummary,
      'server_remux_progressive (audio_adaptation) container=mp4 video=hevc 3840x1600 hdr10 audio=aac 2ch',
    );
  });
}
