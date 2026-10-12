import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

const _session = PrairieSession(serverUrl: 'https://prairie.example', accessToken: 'token', username: 'u', profileId: 'p1');

void main() {
  test('reads effective values with repeated keys params and the device id', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(jsonEncode({
      'items': [
        {'key': 'playback.intro_skip_mode', 'value': 'always', 'source': 'profile'},
        {'key': 'playback.auto_skip_recap', 'value': true, 'source': 'profile_device'},
        {'key': 'playback.auto_play_next', 'value': false, 'source': 'profile'},
      ],
      'revision': 17,
    }), 200));
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter)..deviceId = 'smarttv-abc';

    final skip = await fetchPlaybackSkipSettings(client, _session);

    expect(skip.introSkipMode, IntroSkipMode.always);
    expect(skip.autoSkipRecap, isTrue);
    expect(skip.autoPlayNext, isFalse);
    // Absent from the response: manifest defaults.
    expect(skip.autoSkipCredits, isFalse);
    expect(skip.autoPlayNextPreview, isFalse);
    final request = adapter.requests.single;
    expect(request.uri.path, '/api/v2/settings/values/effective');
    expect(request.uri.queryParametersAll['keys'], contains('playback.intro_skip_mode'));
    expect(request.uri.queryParametersAll['keys'], hasLength(5));
    expect(request.headers['X-Prairie-Device-Id'], 'smarttv-abc');
  });

  test('a server without intro_skip_mode is re-read with the legacy boolean', () async {
    final adapter = FakeHttpAdapter((options) {
      final keys = options.uri.queryParametersAll['keys']!;
      if (keys.contains('playback.intro_skip_mode')) {
        return jsonResponse(jsonEncode({'title': 'Unknown setting key', 'status': 422}), 422);
      }
      return jsonResponse(jsonEncode({
        'items': [
          {'key': 'playback.auto_skip_intro', 'value': true},
        ],
      }), 200);
    });
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

    final skip = await fetchPlaybackSkipSettings(client, _session);

    expect(skip.introSkipMode, IntroSkipMode.always);
    expect(adapter.callCount, 2);
  });

  test('saving writes the profile value then clears the device override', () async {
    final adapter = FakeHttpAdapter((options) => options.method == 'DELETE'
        ? jsonResponse('{"title":"not found"}', 404)
        : jsonResponse(jsonEncode({'key': 'playback.auto_play_next', 'value': false}), 200));
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

    await savePlaybackSkipSetting(client, _session, PlaybackSkipSettings.autoPlayNextKey, false);

    expect(adapter.requests.map((r) => '${r.method} ${r.uri.path}?${r.uri.query}'), [
      'PUT /api/v2/settings/values/playback.auto_play_next?scope=profile',
      'DELETE /api/v2/settings/values/playback.auto_play_next?scope=profile_device',
    ]);
    expect(adapter.requests.first.data, {'value': false});
  });
}
