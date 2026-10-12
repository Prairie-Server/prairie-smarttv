import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

const _session = PrairieSession(serverUrl: 'https://prairie.example', username: 'u', profileId: 'p', accessToken: 'tok');

void main() {
  test('v2 live TV channels, guide and session parse', () async {
    final adapter = FakeHttpAdapter((o) {
      switch (o.uri.path) {
        case '/api/v2/livetv/channels':
          return jsonResponse(
            '{"items":[{"id":"c1","tuner_id":"t1","number":"7.1","callsign":"KABC","name":"ABC","logo_url":null,"hd":true,"enabled":true,"guide_station_id":"s1"},'
            '{"id":"c2","tuner_id":"t1","number":"9","callsign":"OFF","name":"Off","hd":false,"enabled":false}]}',
            200,
          );
        case '/api/v2/livetv/guide':
          expect(o.uri.queryParametersAll['channel_id'], ['c1', 'c2']);
          expect(o.uri.queryParameters.containsKey('channels'), isFalse);
          return jsonResponse(
            '{"items":[{"id":"p1","channel_id":"c1","series_id":"","start":"2026-10-12T10:00:00Z","stop":"2026-10-12T11:00:00Z","title":"News","subtitle":"","description":"","genres":[],"image_url":"","is_new":true,"is_live":false}],'
            '"start":"2026-10-12T10:00:00Z","end":"2026-10-12T22:00:00Z"}',
            200,
          );
        case '/api/v2/livetv/channels/c1/sessions':
          expect(o.method, 'POST');
          return jsonResponse(
            '{"session_id":"ls1","channel_id":"c1","playback_ticket":"pt","stream_url":"/api/v1/livetv/live-hls/ls1/index.m3u8?st=abc","transport":"hls","status":"active","created_at":"2026-10-12T10:00:00Z","stale_after_seconds":90}',
            201,
          );
      }
      return jsonResponse('{}', 404);
    });
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

    final channels = await fetchLiveTvChannels(client, _session);
    expect(channels.map((c) => c.id), ['c1']);
    expect(channels.single.guideStationId, 's1');

    final programs = await fetchLiveTvGuide(client, _session, ['c1', 'c2']);
    expect(programs.single.title, 'News');
    expect(programs.single.isNew, isTrue);

    final started = await startLiveTvSession(client, _session, 'c1');
    expect(started.sessionId, 'ls1');
    expect(started.transport, LiveTvTransport.hls);
    expect(playableLiveUrl(started), '/api/v1/livetv/live-hls/ls1/index.m3u8?st=abc');
  });

  test('Live TV off (409 capability_not_configured) reads as unavailable', () async {
    final adapter = FakeHttpAdapter(
      (_) => ResponseBody.fromString(
        '{"type":"about:blank","title":"Live TV is not configured","status":409,"code":"capability_not_configured"}',
        409,
        headers: {
          Headers.contentTypeHeader: ['application/problem+json'],
        },
      ),
    );
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    expect(await fetchLiveTvChannels(client, _session), isEmpty);
    expect(await fetchLiveTvRecordings(client, _session), isEmpty);
  });

  test('v2 recordings parse from items without start/stop', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse('{"items":[{"id":"r1","channel_id":"c1","status":"scheduled","title":"Movie"}]}', 200),
    );
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    final recordings = await fetchLiveTvRecordings(client, _session);
    expect(recordings.single.id, 'r1');
    expect(recordings.single.start, isNull);
  });
}
