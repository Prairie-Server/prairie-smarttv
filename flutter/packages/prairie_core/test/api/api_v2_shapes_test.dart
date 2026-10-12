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
  test('device poll reads v2 tokens nested under tokens', () async {
    final client = _clientWith(
      (_) => jsonResponse(
        '{"status":"approved","poll_after":0,"opened":true,"profile_id":"","profile_token":"","temporary":false,'
        '"tokens":{"access_token":"at","refresh_token":"rt","expires_in":60,"user":{"id":"7","username":"amy"}}}',
        200,
      ),
    );
    final result = await pollDeviceLogin(client, _server, 'dc');
    expect(result.accessToken, 'at');
    expect(result.refreshToken, 'rt');
    expect(result.username, 'amy');
  });

  test('login parses a v2 string user id', () async {
    late RequestOptions seen;
    final client = _clientWith((o) {
      seen = o;
      return jsonResponse('{"access_token":"at","refresh_token":"rt","expires_in":60,"user":{"id":"7","username":"amy"}}', 200);
    });
    final result = await login(client, _server, const LoginRequest(username: 'amy', password: 'pw'));
    expect(seen.path, endsWith('/api/v2/auth/login'));
    expect(result.user.id, 7);
  });

  test('profiles read the v2 items envelope', () async {
    final client = _clientWith((_) => jsonResponse('{"items":[{"id":"p1","name":"Amy","is_primary":true,"is_child":false}]}', 200));
    final profiles = await listProfiles(client, _server, 'a');
    expect(profiles.single.id, 'p1');
  });

  test('libraries read v2 string ids and drop non-numeric ones', () async {
    final client = _clientWith(
      (_) => jsonResponse('{"items":[{"id":"3","name":"Movies","type":"movie","sort_order":0},{"id":"x","name":"Bad","type":"movie","sort_order":1}]}', 200),
    );
    final libraries = await fetchLibraries(client, _session);
    expect(libraries.map((l) => l.id), [3]);
  });

  test('similar items read the v2 items envelope', () async {
    final client = _clientWith(
      (_) => jsonResponse('{"items":[{"content_id":"c2","title":"Two","type":"movie","status":"available","genres":[],"keywords":[]}]}', 200),
    );
    final result = await fetchSimilarItems(client, _session, 'c1');
    expect(result.cards.single.contentId, 'c2');
  });

  test('item detail reads v2 string file ids', () async {
    final client = _clientWith(
      (_) => jsonResponse(
        '{"content_id":"c1","title":"One","type":"movie","status":"available","genres":[],"keywords":[],"cast":[],"crew":[],'
        '"versions":[{"file_id":"120","resolution":"2160p"}],"user_data":{"last_file_id":"120"}}',
        200,
      ),
    );
    final detail = await fetchItemDetail(client, _session, 'c1');
    expect(detail.versions.single.fileId, 120);
    expect(detail.userData?.lastFileId, 120);
  });
}
