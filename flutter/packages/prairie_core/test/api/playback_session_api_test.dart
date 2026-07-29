import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

void main() {
  group('isPlaybackSessionGone', () {
    test('true for 404 session-gone codes', () {
      expect(
        isPlaybackSessionGone(ApiError('gone', 404, 'playback_session_not_found')),
        isTrue,
      );
      expect(isPlaybackSessionGone(ApiError('gone', 404, 'not_found')), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404, 'session_not_found')), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404)), isTrue);
      expect(isPlaybackSessionGone(ApiError('gone', 404, '')), isTrue);
    });

    test('false for other statuses or codes', () {
      expect(isPlaybackSessionGone(ApiError('nope', 500, 'playback_session_not_found')), isFalse);
      expect(isPlaybackSessionGone(ApiError('nope', 404, 'forbidden')), isFalse);
      expect(isPlaybackSessionGone(StateError('x')), isFalse);
    });
  });

  group('switchPlaybackAudio', () {
    test('PATCHes audio track and parses the response', () async {
      final adapter = FakeHttpAdapter((options) {
        expect(options.method, 'PATCH');
        expect(options.uri.path, contains('/api/v1/playback/sess-1/audio'));
        expect(options.data.toString(), contains('audio_track_index: 2'));
        return jsonResponse(
          '{"audio_track_index":2,"play_method":"remux","stream_url":"/hls/x.m3u8","player_start_seconds":12.5}',
          200,
        );
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      const session = PrairieSession(
        serverUrl: 'https://prairie.example',
        username: 'u',
        profileId: 'p',
        accessToken: 'tok',
      );

      final updated = await switchPlaybackAudio(client, session, 'sess-1', 2, 12.5);
      expect(updated.audioTrackIndex, 2);
      expect(updated.playMethod, 'remux');
      expect(updated.streamUrl, '/hls/x.m3u8');
      expect(updated.playerStartSeconds, 12.5);
    });
  });
}
