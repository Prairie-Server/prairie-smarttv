import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

// Property sets of the v2 openapi request schemas (all additionalProperties:
// false), copied from server contracts/api/v2/openapi.json. A body with any
// other key is rejected with 422, so every builder is checked against these.
const _replanBodyProperties = {
  'attempt_count', 'attempted_plan_keys', 'bandwidth_cap_kbps', 'bandwidth_estimate_kbps',
  'client_capabilities', 'client_features', 'client_playback_context', 'failed_plan_id',
  'failure', 'installation_id', 'local_mutations', 'metered', 'operation', 'plan_attempt_id',
  'plan_attempt_key', 'playback_attempt_id', 'position_seconds', 'protocol_version',
  'quality_preference', 'replan_request_id', 'selected_tracks',
};
const _replanBodyRequired = {
  'installation_id', 'protocol_version', 'playback_attempt_id', 'replan_request_id',
  'failed_plan_id', 'plan_attempt_id', 'plan_attempt_key', 'attempted_plan_keys',
  'attempt_count', 'quality_preference', 'position_seconds', 'metered', 'selected_tracks',
  'client_capabilities', 'client_playback_context',
};
const _failureProperties = {'classification', 'decoder_name', 'message'};
const _trackIdentityProperties = {'id', 'index'};
const _progressBodyProperties = {'installation_id', 'is_paused', 'position', 'sequence'};
const _stopBodyProperties = {'installation_id', 'is_paused', 'position', 'sequence', 'stop_id'};
const _routeEventProperties = {
  'applied_quirk_ids', 'diagnostics', 'event', 'event_id', 'failure_classification',
  'fallback_reason', 'installation_id', 'output_context_id', 'plan_attempt_id',
  'plan_attempt_key', 'plan_id', 'playback_attempt_id', 'protocol_version',
  'quirk_registry_revision', 'session_id',
};
const _routeEventRequired = {'installation_id', 'event_id', 'protocol_version', 'playback_attempt_id', 'event', 'diagnostics'};

const _session = PrairieSession(serverUrl: 'https://prairie.example', username: 'u', profileId: 'p', accessToken: 'tok');
const _input = BuildPlaybackStartInput(fileId: 515, profileId: 'p', maxAudioChannels: 6);
const _capabilities =
    '{"protocol_versions":[3],"features":["seek_reanchor_v1"],"deliveries":[],"revision":"r",'
    '"state":"available","allowed":true,"installation_id":"inst-1"}';

/// A signed, server-anchored progressive remux URL. The `%2B` / `%3D` and
/// parameter order are part of the signature: any re-encoding breaks it.
const _signedRemuxUrl = '/api/v2/stream/s1?seek=1234.5&st=ab%2Bcd%3D&sig=Zm9v%2F';

Map<String, dynamic> _decisionJson({
  String delivery = 'server_remux_progressive',
  String protocol = 'http_progressive',
  String url = _signedRemuxUrl,
  Map<String, dynamic>? timeline,
  List<String> serverFeatures = const ['seek_reanchor_v1'],
  String planId = 'plan-0001',
  String planKey = 'key-0001',
}) => {
  'protocol_version': 3,
  'server_features': serverFeatures,
  'outcome': 'playable',
  'session_id': 's1',
  'playback_plan': {
    'session_id': 's1',
    'plan_id': planId,
    'plan_attempt_key': planKey,
    'delivery': delivery,
    'requested_media_file_id': '515',
    'effective_media_file_id': '515',
    'stream': {
      'protocol': protocol,
      'url': url,
      'headers': {'X-Prairie-Stream': 'v'},
      'header_refresh': 'none',
    },
    'timeline': timeline ??
        {
          'source_start_seconds': 1234.5,
          'stream_origin_seconds': 1230.0,
          'player_start_seconds': 4.5,
          'timeline_offset_seconds': 1230.0,
          'seek_window_start_seconds': 1230.0,
          'can_seek_anywhere': false,
          'seek_restoration': 'source_position',
        },
    'source': {'media_file_id': '515', 'duration_seconds': 7200},
    'selected_tracks': {
      'audio': {'id': 'a2', 'index': 2, 'codec': 'ac3', 'language': 'eng'},
      'subtitle': {'id': 's1', 'index': 4, 'format': 'srt'},
    },
    'effective_recipe': {},
  },
};

Map<String, dynamic> _body(RequestOptions o) =>
    o.data is String ? jsonDecode(o.data as String) as Map<String, dynamic> : Map<String, dynamic>.from(o.data as Map);

void _expectShape(Map<String, dynamic> body, Set<String> allowed, [Set<String> required = const {}]) {
  expect(body.keys.toSet().difference(allowed), isEmpty, reason: 'keys outside the schema');
  expect(required.difference(body.keys.toSet()), isEmpty, reason: 'missing required keys');
}

/// Adapter whose handler may be async, tracking how many requests overlap.
class _AsyncAdapter implements HttpClientAdapter {
  _AsyncAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      return await handler(options);
    } finally {
      inFlight--;
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    resetPlaybackV2StateForTest();
    playbackRetryPause = (_) async {};
  });

  group('v3 decision adapter', () {
    test('carries timeline, stream headers, server features and track identities', () {
      final parsed = PlaybackSessionResponse.fromJson(_decisionJson());
      final t = parsed.timeline!;
      expect(t.sourceStartSeconds, 1234.5);
      expect(t.streamOriginSeconds, 1230.0);
      expect(t.playerStartSeconds, 4.5);
      expect(t.timelineOffsetSeconds, 1230.0);
      expect(t.seekWindowStartSeconds, 1230.0);
      expect(t.seekWindowEndSeconds, isNull);
      expect(t.canSeekAnywhere, isFalse);
      expect(parsed.position, 1234.5);
      expect(parsed.streamUrl, _signedRemuxUrl);
      expect(parsed.streamHeaders, {'X-Prairie-Stream': 'v'});
      expect(parsed.streamHeaderRefresh, 'none');
      expect(parsed.supportsSeekReanchor, isTrue);
      expect(parsed.planAttemptId, hasLength(32));
      expect(parsed.selectedTracks, {
        'audio': {'id': 'a2', 'index': 2},
        'subtitle': {'id': 's1', 'index': 4},
      });
    });

    test('seek_reanchor is unavailable without the server feature', () {
      final parsed = PlaybackSessionResponse.fromJson(_decisionJson(serverFeatures: const []));
      expect(parsed.supportsSeekReanchor, isFalse);
    });

    test('a terminal decision surfaces the server message', () {
      expect(
        () => PlaybackSessionResponse.fromJson({
          'protocol_version': 3,
          'outcome': 'adaptation_unavailable',
          'terminal': {'reason': 'no_compatible_delivery', 'message': 'Nothing fits.', 'retryable': false},
        }),
        throwsA(isA<PlaybackTerminalError>()
            .having((e) => e.message, 'message', 'Nothing fits.')
            .having((e) => e.reason, 'reason', 'no_compatible_delivery')),
      );
    });
  });

  group('prepareProtocolV3Decision', () {
    final client = ApiClient(dio: Dio()..httpClientAdapter = FakeHttpAdapter((_) => fail('no network expected')));

    test('never rewrites the signed remux stream.url (no seek= of its own)', () async {
      final decision = PlaybackSessionResponse.fromJson(_decisionJson());
      final prepared = await prepareProtocolV3Decision(client, _session, decision, 999);
      expect(prepared.streamUrl, 'https://prairie.example$_signedRemuxUrl');
      // Progressive remux cannot native-seek on the TV: t=0 is the keyframe
      // origin the server resolved, not the requested position.
      expect(prepared.playerStartSeconds, 0);
      expect(prepared.streamOriginSeconds, 1230.0);
    });

    test('direct play starts at timeline.player_start_seconds (resume)', () async {
      final decision = PlaybackSessionResponse.fromJson(_decisionJson(
        delivery: 'original_http',
        url: '/api/v2/stream/s1/original?st=x%2By',
        timeline: {
          'source_start_seconds': 2710.0,
          'stream_origin_seconds': 0,
          'player_start_seconds': 2710.0,
          'timeline_offset_seconds': 0,
          'can_seek_anywhere': true,
          'seek_restoration': 'player_position',
        },
      ));
      // The requested seek (0 here) must not override the plan.
      final prepared = await prepareProtocolV3Decision(client, _session, decision, 0);
      expect(prepared.streamUrl, 'https://prairie.example/api/v2/stream/s1/original?st=x%2By');
      expect(prepared.playerStartSeconds, 2710.0);
      expect(prepared.streamOriginSeconds, 0);
    });

    test('HLS offsets come from the timeline, not the requested seek', () {
      final decision = PlaybackSessionResponse.fromJson(_decisionJson(
        delivery: 'server_transcode_hls',
        protocol: 'hls',
        url: '/api/v2/playback/transcode/s1/master.m3u8?st=x',
        timeline: {
          'source_start_seconds': 3601.0,
          'stream_origin_seconds': 3600.0,
          'player_start_seconds': 1.0,
          'timeline_offset_seconds': 3600.0,
          'seek_window_start_seconds': 3600.0,
          'seek_window_end_seconds': 7200.0,
          'can_seek_anywhere': false,
        },
      ));
      final offsets = protocolV3StartOffsets(decision, fallbackSeekSeconds: 3601);
      expect(offsets.playerStartSeconds, 1.0);
      expect(offsets.streamOriginSeconds, 3600.0);
    });
  });

  group('PlaybackTimeline.canSeekLocally', () {
    test('seek anywhere always seeks locally', () {
      expect(const PlaybackTimeline(canSeekAnywhere: true).canSeekLocally(99999), isTrue);
    });

    test('closed window bounds both ends', () {
      const t = PlaybackTimeline(seekWindowStartSeconds: 100, seekWindowEndSeconds: 200);
      expect(t.canSeekLocally(150), isTrue);
      expect(t.canSeekLocally(99), isFalse);
      expect(t.canSeekLocally(201), isFalse);
    });

    test('open window is bounded by what has been produced', () {
      const t = PlaybackTimeline(seekWindowStartSeconds: 100);
      expect(t.canSeekLocally(150, producedEndSeconds: 160), isTrue);
      expect(t.canSeekLocally(170, producedEndSeconds: 160), isFalse);
      expect(t.canSeekLocally(150), isFalse);
    });

    test('no published window lets the native player try', () {
      expect(const PlaybackTimeline().canSeekLocally(42), isTrue);
    });
  });

  group('replan bodies', () {
    PlaybackSessionResponse started() => PlaybackSessionResponse.fromJson(_decisionJson()).copyWith(
      playbackAttemptId: 'attempt-12345678',
      clientFeatures: const ['playback_plan_v3'],
      clientCapabilities: const {'video_evidence': 'declared'},
      clientPlaybackContext: const {'protocol_version': 3},
    );

    test('intent replans reset attempted keys and count and keep plan tracks', () {
      final current = started().copyWith(attemptedPlanKeys: const ['old-key-1'], attemptCount: 3);
      final body = buildReplanBody(
        current,
        operation: 'seek_reanchor',
        qualityPreference: 'auto',
        positionSeconds: 42,
        replanRequestId: 'replan-12345678',
        installationId: 'inst-1',
      );
      _expectShape(body, _replanBodyProperties, _replanBodyRequired);
      expect(body['attempted_plan_keys'], isEmpty);
      expect(body['attempt_count'], 1);
      expect(body['plan_attempt_id'], current.planAttemptId);
      expect(body.containsKey('failure'), isFalse);
      expect(body['selected_tracks'], {
        'audio': {'id': 'a2', 'index': 2},
        'subtitle': {'id': 's1', 'index': 4},
      });
      for (final track in (body['selected_tracks'] as Map).values) {
        expect((track as Map).keys.toSet().difference(_trackIdentityProperties), isEmpty);
      }
    });

    test('failure recovery folds in the failed key and carries a schema-valid failure', () {
      final current = started().copyWith(attemptedPlanKeys: const ['old-key-1'], attemptCount: 2);
      final body = buildReplanBody(
        current,
        operation: 'failure_recovery',
        qualityPreference: 'auto',
        positionSeconds: 42,
        replanRequestId: 'replan-12345678',
        installationId: 'inst-1',
        failure: playbackFailureV3('decoder_failure', 'Not supported format'),
      );
      _expectShape(body, _replanBodyProperties, _replanBodyRequired);
      expect(body['attempted_plan_keys'], ['old-key-1', 'key-0001']);
      expect(body['attempt_count'], 2);
      final failure = body['failure'] as Map<String, dynamic>;
      _expectShape(failure, _failureProperties, {'classification'});
      expect(failure, {'classification': 'decoder_failure', 'message': 'Not supported format'});
    });

    test('attempted keys are capped at the schema maximum', () {
      final keys = [for (var i = 0; i < 20; i++) 'key-$i-abcdef'];
      final body = buildReplanBody(
        started().copyWith(attemptedPlanKeys: keys),
        operation: 'failure_recovery',
        qualityPreference: 'auto',
        positionSeconds: 0,
        replanRequestId: 'replan-12345678',
      );
      expect((body['attempted_plan_keys'] as List).length, maxAttemptedPlanKeysV3);
      expect((body['attempted_plan_keys'] as List).last, 'key-0001');
    });

    test('replanPlaybackFailure increments attempt_count and stops past the limit', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(jsonEncode(_decisionJson()), 201);
        expect(o.uri.path, '/api/v2/playback/s1/replan');
        _expectShape(_body(o), _replanBodyProperties, _replanBodyRequired);
        return jsonResponse(jsonEncode(_decisionJson(planId: 'plan-0002', planKey: 'key-0002')), 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final first = await startPlayback(client, _session, _input);
      expect(first.attemptCount, 1);
      final second = await replanPlaybackFailure(client, _session, first, classification: 'transport_stall', positionSeconds: 10);
      expect(_body(adapter.requests.last)['operation'], 'failure_recovery');
      expect(_body(adapter.requests.last)['attempt_count'], 1);
      expect(second.attemptCount, 2);
      expect(second.attemptedPlanKeys, ['key-0001']);
      expect(second.planId, 'plan-0002');

      final exhausted = second.copyWith(attemptCount: maxPlaybackAttemptCountV3 + 1);
      await expectLater(
        replanPlaybackFailure(client, _session, exhausted, classification: 'transport_stall', positionSeconds: 10),
        throwsA(isA<PlaybackRecoveryExhaustedError>()),
      );
    });

    test('an intent replan after a recovery resets the counters', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(jsonEncode(_decisionJson()), 201);
        return jsonResponse(jsonEncode(_decisionJson(planId: 'plan-0003', planKey: 'key-0003')), 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final first = await startPlayback(client, _session, _input);
      final recovered = await replanPlaybackFailure(client, _session, first, classification: 'player_failure', positionSeconds: 1);
      final seeked = await replanPlaybackSeek(client, _session, recovered, positionSeconds: 99);
      expect(_body(adapter.requests.last)['operation'], 'seek_reanchor');
      expect(_body(adapter.requests.last)['attempted_plan_keys'], isEmpty);
      expect(seeked.attemptCount, 1);
      expect(seeked.attemptedPlanKeys, isEmpty);
    });
  });

  group('start retry', () {
    test('retries a transient failure with the identical body', () async {
      var starts = 0;
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        starts++;
        if (starts == 1) return jsonResponse('{"title":"unavailable"}', 503);
        if (starts == 2) throw const SocketExceptionLike();
        return jsonResponse(jsonEncode(_decisionJson()), 201);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final started = await startPlayback(client, _session, _input);
      expect(started.sessionId, 's1');
      final bodies = adapter.requests.where((o) => o.uri.path == '/api/v2/playback/start').map((o) => jsonEncode(_body(o))).toList();
      expect(bodies, hasLength(3));
      expect(bodies.toSet(), hasLength(1), reason: 'every retry must send the identical body');
    });

    test('does not retry a refusal', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        return jsonResponse('{"type":"https://prairie.example/problems/validation_failed","detail":"bad body"}', 422);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      await expectLater(
        startPlayback(client, _session, _input),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'validation_failed').having((e) => e.message, 'message', 'bad body')),
      );
      expect(adapter.requests.where((o) => o.uri.path == '/api/v2/playback/start'), hasLength(1));
    });

    test('isTransientPlaybackError', () {
      expect(isTransientPlaybackError(ApiError('x', 502)), isTrue);
      expect(isTransientPlaybackError(ApiError('x', 0)), isTrue);
      expect(isTransientPlaybackError(ApiError('x', 404)), isFalse);
      expect(isTransientPlaybackError(DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError)), isTrue);
      expect(isTransientPlaybackError(DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel)), isFalse);
    });
  });

  group('progress and stop', () {
    test('progress is serialized with monotonic sequences and retries transient failures', () async {
      var progressCalls = 0;
      final adapter = _AsyncAdapter((o) async {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(jsonEncode(_decisionJson()), 201);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (o.uri.path.endsWith('/progress') && ++progressCalls == 2) return jsonResponse('{}', 503);
        return jsonResponse('{"outcome":"stopped"}', 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      await startPlayback(client, _session, _input);
      await Future.wait([
        reportPlaybackProgress(client, _session, 's1', 1, false),
        reportPlaybackProgress(client, _session, 's1', 2, false),
        reportPlaybackProgress(client, _session, 's1', 3, false),
      ]);
      final progress = adapter.requests.where((o) => o.uri.path.endsWith('/progress')).map(_body).toList();
      expect(adapter.maxInFlight, 1, reason: 'one progress request in flight at a time');
      // Sample 2 failed once with a 503 and was resent with the same sequence.
      expect(progress.map((b) => b['sequence']).toList(), [1, 2, 2, 3]);
      for (final b in progress) {
        _expectShape(b, _progressBodyProperties, _progressBodyProperties);
      }

      await stopPlaybackSession(client, _session, 's1', position: 3.5);
      final stop = adapter.requests.last;
      expect(stop.method, 'DELETE');
      final stopBody = _body(stop);
      _expectShape(stopBody, _stopBodyProperties, {'installation_id', 'stop_id'});
      expect(stopBody['position'], 3.5);
      expect(stopBody['is_paused'], isTrue);
      expect(stopBody['sequence'], 4);
    });

    test('stop without a position sends the latest sample and keeps its body across retries', () async {
      var stops = 0;
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(jsonEncode(_decisionJson()), 201);
        if (o.method == 'DELETE' && ++stops == 1) return jsonResponse('{}', 500);
        return jsonResponse('{"outcome":"stopped"}', 200);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      await startPlayback(client, _session, _input);
      await reportPlaybackProgress(client, _session, 's1', 12, true);
      await stopPlaybackSession(client, _session, 's1');
      final deletes = adapter.requests.where((o) => o.method == 'DELETE').map((o) => jsonEncode(_body(o))).toList();
      expect(deletes, hasLength(2));
      expect(deletes.toSet(), hasLength(1));
      final stopBody = jsonDecode(deletes.first) as Map<String, dynamic>;
      expect(stopBody['position'], 12);
      expect(stopBody['sequence'], 2);
      // Progress after stop is dropped.
      await reportPlaybackProgress(client, _session, 's1', 13, false);
      expect(adapter.requests.last.method, 'DELETE');
    });
  });

  group('route events', () {
    test('builds a schema-valid body for a v2 session only', () async {
      final adapter = FakeHttpAdapter((o) {
        if (o.uri.path == '/api/v2/playback/capabilities') return jsonResponse(_capabilities, 200);
        if (o.uri.path == '/api/v2/playback/start') return jsonResponse(jsonEncode(_decisionJson()), 201);
        expect(o.uri.path, '/api/v2/playback/route-events');
        return ResponseBody.fromString('', 202);
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
      final started = await startPlayback(client, _session, _input);
      await reportPlaybackRouteEvent(
        client,
        _session,
        started,
        'plan_failed',
        failureClassification: 'decoder_failure',
        diagnostics: {'error_cause': 'x' * 400},
      );
      final body = _body(adapter.requests.last);
      _expectShape(body, _routeEventProperties, _routeEventRequired);
      expect(body['event'], 'plan_failed');
      expect(body['plan_attempt_id'], started.planAttemptId);
      expect((body['diagnostics'] as Map)['error_cause'], hasLength(256));

      final unregistered = PlaybackSessionResponse.fromJson(_decisionJson()).copyWith(sessionId: 'other', playbackAttemptId: 'attempt-12345678');
      expect(buildRouteEventBody(unregistered, 'first_frame'), isNull);
      expect(buildRouteEventBody(started, 'not_an_event'), isNull);
    });
  });

  test('classifyPlaybackFailure uses the Android TV vocabulary', () {
    expect(classifyPlaybackFailure('Playback stalled — the stream stopped producing media.'), 'transport_stall');
    expect(classifyPlaybackFailure(StateError('Player initialize timed out after 90s')), 'transport_stall');
    expect(classifyPlaybackFailure('Not supported format'), 'decoder_failure');
    expect(classifyPlaybackFailure(ApiError('forbidden', 403)), 'http_failure');
    expect(classifyPlaybackFailure('something odd'), 'player_failure');
  });

  test('live TV heartbeat posts to the session heartbeat route', () async {
    final adapter = FakeHttpAdapter((o) {
      expect(o.method, 'POST');
      expect(o.uri.path, '/api/v1/livetv/sessions/live%201/heartbeat');
      return ResponseBody.fromString('', 204);
    });
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    await heartbeatLiveTvSession(client, _session, 'live 1');
    expect(adapter.callCount, 1);
    expect(liveTvHeartbeatInterval, const Duration(seconds: 30));
  });
}

/// Thrown from the fake adapter to look like a dropped connection.
class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
