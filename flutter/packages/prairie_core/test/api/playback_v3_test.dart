import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

void main() {
  test('builds a protocol-v3 start body accepted by the v1 bridge', () {
    final body = buildPlaybackStartRequest(
      const BuildPlaybackStartInput(
        fileId: 42,
        profileId: 'profile-1',
        startPosition: 12.5,
        forcedPlayMethod: PlayMethod.direct,
        playbackAttemptId: 'attempt-12345678',
      ),
    );

    expect(body['protocol_version'], 3);
    expect(body['file_id'], 42);
    expect(body['profile_id'], 'profile-1');
    expect(body['playback_attempt_id'], 'attempt-12345678');
    expect(body['client_features'], contains('playback_plan_v3'));
    expect(body['client_capabilities']['video_evidence'], 'declared');
    expect(body['client_capabilities']['audio_evidence'], 'declared');
    expect(body['client_playback_context']['protocol_version'], 3);

    final deliveries = body['client_playback_context']['deliveries'] as Map<String, dynamic>;
    expect(deliveries['original_http']['enabled'], isTrue);
    expect(deliveries['progressive']['enabled'], isFalse);
    expect(deliveries['hls']['enabled'], isFalse);
  });

  test('an explicit zero start position is sent, so Start Over does not resume', () {
    Map<String, dynamic> body(double? start) => buildPlaybackStartRequest(
      BuildPlaybackStartInput(fileId: 42, profileId: 'profile-1', startPosition: start, playbackAttemptId: 'attempt-12345678'),
    );

    expect(body(0)['start_position'], 0);
    expect(body(12.5)['start_position'], 12.5);
    // Omitted is the resume request; it must stay distinct from zero.
    expect(body(null).containsKey('start_position'), isFalse);
  });

  test('force transcode advertises HLS only', () {
    final body = buildPlaybackStartRequest(
      const BuildPlaybackStartInput(
        fileId: 42,
        profileId: 'profile-1',
        forcedPlayMethod: PlayMethod.transcode,
        playbackAttemptId: 'attempt-12345678',
      ),
    );

    final deliveries = body['client_playback_context']['deliveries'] as Map<String, dynamic>;
    expect(deliveries['original_http']['enabled'], isFalse);
    expect(deliveries['progressive']['enabled'], isFalse);
    expect(deliveries['hls']['enabled'], isTrue);
  });

  test('parses a protocol-v3 playable decision into the existing session model', () {
    final session = PlaybackSessionResponse.fromJson({
      'protocol_version': 3,
      'outcome': 'playable',
      'session_id': 'sess-1',
      'playback_plan': {
        'protocol_version': 3,
        'plan_id': 'plan-12345678',
        'delivery': 'server_remux_progressive',
        'stream': {
          'url': '/api/v1/stream/sess-1',
          'protocol': 'http_progressive',
        },
        'timeline': {
          'source_start_seconds': 0,
          'stream_origin_seconds': 10,
          'player_start_seconds': 0,
          'timeline_offset_seconds': 10,
          'can_seek_anywhere': false,
          'seek_restoration': 'player_position',
        },
        'selected_tracks': {
          'audio': {'id': 'a1', 'index': 2},
        },
        'effective_recipe': {
          'video_codec': 'hevc',
          'audio_codec': 'aac',
        },
        'source': {
          'media_file_id': '42',
          'duration_seconds': 3600,
        },
        'requested_media_file_id': '42',
        'effective_media_file_id': '42',
      },
    });

    expect(session.sessionId, 'sess-1');
    expect(session.mediaFileId, 42);
    expect(session.playMethod, 'remux');
    expect(session.streamUrl, '/api/v1/stream/sess-1');
    expect(session.audioTrackIndex, 2);
    expect(session.position, 10);
    expect(session.durationSeconds, 3600);
    expect(session.playbackInfo?.streamType, 'http_progressive');
    expect(session.playbackInfo?.videoCodec, 'hevc');
  });

  test('rejects a non-playable protocol-v3 decision', () {
    expect(
      () => PlaybackSessionResponse.fromJson({
        'protocol_version': 3,
        'outcome': 'adaptation_unavailable',
        'terminal': {'reason': 'no_compatible_delivery'},
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
