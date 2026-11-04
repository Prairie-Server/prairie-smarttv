import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import '../api/fake_http_adapter.dart';

const _server = 'https://prairie.example.com';
const _session = PrairieSession(serverUrl: _server, accessToken: 'a', username: 'u', profileId: 'p1');

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

void main() {
  test('a title page reads its theme songs and their owner', () {
    final themes = ThemeSongSet.fromJson({
      'owner_id': 'series-1',
      'items': [
        {'id': 't1', 'title': 'Main Title', 'container': 'mp3', 'duration_seconds': 42},
        {'id': '', 'title': 'no id'},
      ],
    });
    expect(themes!.ownerId, 'series-1');
    expect(themes.items.single.id, 't1');
    expect(themes.items.single.durationSeconds, 42);
    expect(ThemeSongSet.fromJson(null), isNull);
    expect(ThemeSongSet.fromJson({'owner_id': 'x', 'items': []}), isNull);
    expect(ThemeSongSet.fromJson({'items': [{'id': 't1'}]}), isNull);
  });

  test('theme music is available only when the server and the viewer allow it', () async {
    var body = '{"state":"available","allowed":true}';
    var status = 200;
    final client = _clientWith((o) {
      expect(o.uri.path, '/api/v2/catalog/themes/capabilities');
      return jsonResponse(body, status);
    });
    expect((await fetchThemeMusicCapability(client, _session)).available, isTrue);
    body = '{"state":"available","allowed":false}';
    expect((await fetchThemeMusicCapability(client, _session)).available, isFalse);
    body = '{"state":"disabled","allowed":true}';
    expect((await fetchThemeMusicCapability(client, _session)).available, isFalse);
    body = '{"error":"not found"}';
    status = 404;
    expect((await fetchThemeMusicCapability(client, _session)).available, isFalse);
  });

  test('a grant names the formats the TV plays and resolves a relative url', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse(
        '{"url":"/api/v2/catalog/items/s1/themes/t1/audio?grant=g","delivery":"converted",'
        '"content_type":"audio/mp4","expires_at":"2026-11-03T12:00:00Z"}',
        200,
      );
    });
    final grant = await requestThemeMusic(client, _session, ownerId: 's1', themeId: 't1');
    expect(seen.method, 'POST');
    expect(seen.uri.path, '/api/v2/catalog/items/s1/themes/t1/playback');
    final sent = seen.data is String ? jsonDecode(seen.data as String) : seen.data;
    expect((sent as Map)['accepted_formats'], themeMusicAcceptedFormats);
    expect(grant.url, '$_server/api/v2/catalog/items/s1/themes/t1/audio?grant=g');
    expect(grant.converted, isTrue);
  });

  test('an absolute grant on a proxy node is kept as sent', () async {
    final client = _clientWith(
      (_) => jsonResponse('{"url":"https://node2.example.com/a?g=1","delivery":"original","content_type":"audio/mpeg"}', 200),
    );
    final grant = await requestThemeMusic(client, _session, ownerId: 's1', themeId: 't1');
    expect(grant.url, 'https://node2.example.com/a?g=1');
    expect(grant.converted, isFalse);
  });

  test('preferences read both keys, default off, and hide on servers without them', () async {
    var status = 200;
    late Uri seen;
    final client = _clientWith((o) {
      seen = o.uri;
      return status == 200
          ? jsonResponse('{"items":[{"key":"ui.theme_music_enabled","value":true},{"key":"ui.theme_music_loop","value":false}]}', 200)
          : jsonResponse('{"error":"unknown key"}', status);
    });
    final settings = await fetchThemeMusicSettings(client, _session);
    expect(seen.queryParametersAll['keys'], [ThemeMusicSettings.enabledKey, ThemeMusicSettings.loopKey]);
    expect(settings!.enabled, isTrue);
    expect(settings.loop, isFalse);
    expect(ThemeMusicSettings.fromValues(const {}).enabled, isFalse);
    status = 422;
    expect(await fetchThemeMusicSettings(client, _session), isNull);
  });

  test('a toggle is saved for this profile on this TV', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse('{}', 200);
    });
    await saveThemeMusicSetting(client, _session, ThemeMusicSettings.loopKey, true);
    expect(seen.method, 'PUT');
    expect(seen.uri.path, '/api/v2/settings/values/ui.theme_music_loop');
    expect(seen.uri.queryParameters['scope'], 'profile_device');
  });
}
