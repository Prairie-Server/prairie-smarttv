import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

void main() {
  test('a refresh fires the client-wide hook so the session can persist it', () async {
    final adapter = FakeHttpAdapter((o) {
      if (o.uri.path == '/api/v1/auth/refresh') {
        return jsonResponse('{"access_token":"fresh","refresh_token":"r2"}', 200);
      }
      final auth = o.headers['Authorization'] as String?;
      return auth == 'Bearer fresh'
          ? jsonResponse('{"ok":true}', 200)
          : jsonResponse('{"error":"invalid_token"}', 401);
    });
    final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);
    String? saved;
    client.onTokensRefreshed = (access, _) => saved = access;

    await client.request<Map<String, dynamic>>(
      const ApiClientOptions(serverUrl: 'https://prairie.example', accessToken: 'stale', refreshToken: 'r1'),
      '/api/v1/watch/x',
    );
    expect(saved, 'fresh');
  });

  test('a v2 st-granted stream URL is not given the session token', () {
    const session = PlaybackSessionResponse(
      sessionId: 's', mediaFileId: 1, playMethod: 'direct', position: 0, isPaused: false,
      streamUrl: '/api/v2/stream/abc?st=grant', audioTrackIndex: 0,
    );
    final url = resolvePlaybackStreamUrl('https://prairie.example', session, 'stale');
    expect(url, 'https://prairie.example/api/v2/stream/abc?st=grant');
  });
}
