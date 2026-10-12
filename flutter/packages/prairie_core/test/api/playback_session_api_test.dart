import 'dart:convert';

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

  group('protocol v2 lifecycle', () {
    const session = PrairieSession(
      serverUrl: 'https://prairie.example',
      username: 'u',
      profileId: 'p',
      accessToken: 'tok',
    );
    const input = BuildPlaybackStartInput(fileId: 515, profileId: 'p', maxAudioChannels: 6);
    const decision =
        '{"protocol_version":3,"server_features":[],"outcome":"playable","session_id":"s1",'
        '"playback_plan":{"session_id":"s1","plan_id":"plan-0001","plan_attempt_key":"key-0001",'
        '"delivery":"hls","requested_media_file_id":"515","effective_media_file_id":"515",'
        '"stream":{"protocol":"hls","url":"/api/v2/playback/transcode/s1/master.m3u8?token=x"},'
        '"timeline":{},"source":{"media_file_id":"515"},"selected_tracks":{"audio":{"id":"a","index":2}},'
        '"effective_recipe":{}}}';
    const capabilities =
        '{"protocol_versions":[3],"features":[],"deliveries":[],"revision":"r","state":"available",'
        '"allowed":true,"installation_id":"inst-1"}';

    setUp(resetPlaybackV2StateForTest);

    Map<String, dynamic> body(RequestOptions o) =>
        o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : Map<String, dynamic>.from(o.data as Map);

    test('starts on v2 with installation, string file id and no v1 extras', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(capabilities, 200);
        expect(o.uri.path, '/api/v2/playback/start');
        final b = body(o);
        expect(b['installation_id'], 'inst-1');
        expect(b['file_id'], '515');
        expect(b.containsKey('max_audio_channels'), isFalse);
        return jsonResponse(decision, 201);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final started = await startPlayback(client, session, input);
      expect(started.sessionId, 's1');
      expect(started.mediaFileId, 515);
      expect(started.audioTrackIndex, 2);
      expect(started.isProtocolV3, isTrue);
    });

    test('sequences progress and stops once on v2', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(decision, 201);
        return jsonResponse('{"outcome":"applied"}', 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      await startPlayback(client, session, input);
      await reportPlaybackProgress(client, session, 's1', 1, false);
      await reportPlaybackProgress(client, session, 's1', 2, true);
      await stopPlaybackSession(client, session, 's1');

      final progress = adapter.requests.where((o) => o.uri.path.endsWith('/progress')).toList();
      expect(progress.map((o) => o.uri.path).toSet(), {'/api/v2/playback/s1/progress'});
      expect(progress.map((o) => body(o)['sequence']).toList(), [1, 2]);
      expect(progress.every((o) => body(o)['installation_id'] == 'inst-1'), isTrue);
      final stop = adapter.requests.last;
      expect(stop.method, 'DELETE');
      expect(stop.uri.path, '/api/v2/playback/s1');
      expect(body(stop)['installation_id'], 'inst-1');
      // v2 rejects anything but a canonical UUID here.
      expect(body(stop)['stop_id'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    });

    test('replans an audio change on v2 as a track_change', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(decision, 201);
        expect(o.uri.path, '/api/v2/playback/s1/replan');
        final b = body(o);
        expect(b['operation'], 'track_change');
        expect(b['installation_id'], 'inst-1');
        expect(b['selected_tracks'], {'audio': {'id': '', 'index': 1}});
        return jsonResponse(decision, 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final started = await startPlayback(client, session, input);
      await replanPlaybackAudio(client, session, started, audioTrackIndex: 1, positionSeconds: 30);
    });

    test('refuses to start when the server offers no installation', () async {
      final adapter = FakeHttpAdapter((o) {
        expect(o.uri.path, '/api/v2/playback/capabilities');
        return jsonResponse('{"protocol_versions":[3],"state":"not_configured","allowed":false}', 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        startPlayback(client, session, input),
        throwsA(isA<PlaybackTerminalError>().having((e) => e.message, 'message', "This server can't start playback.")),
      );
      expect(adapter.requests, hasLength(1));
    });
  });
}
