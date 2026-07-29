import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

void main() {
  group('buildStreamUrl', () {
    test('joins relative stream paths and appends token', () {
      expect(
        buildStreamUrl('https://prairie.example', '/api/v1/stream/abc', 'tok'),
        'https://prairie.example/api/v1/stream/abc?token=tok',
      );
    });

    test('appends token to same-origin absolute URLs with existing query params', () {
      expect(
        buildStreamUrl('https://prairie.example', 'https://prairie.example/s?st=1', 'tok'),
        'https://prairie.example/s?st=1&token=tok',
      );
    });

    test('does not attach the session token to cross-origin absolute URLs', () {
      expect(
        buildStreamUrl('https://prairie.example', 'https://cdn.example/s?st=1', 'tok'),
        'https://cdn.example/s?st=1',
      );
    });

    test('appends profile_id for same-origin streams when provided', () {
      expect(
        buildStreamUrl('https://prairie.example', '/live.m3u8', null, 'p1'),
        'https://prairie.example/live.m3u8?profile_id=p1',
      );
    });

    test('returns the base URL untouched when there is nothing to append', () {
      expect(buildStreamUrl('https://prairie.example', '/stream', null), 'https://prairie.example/stream');
    });

    test('does not emit an empty token= param when the access token is empty', () {
      expect(buildStreamUrl('https://prairie.example', '/stream', ''), 'https://prairie.example/stream');
    });
  });

  group('isAuthLoginPath', () {
    test('matches login/refresh routes with optional query/trailing slash', () {
      expect(isAuthLoginPath('/api/v1/auth/login'), true);
      expect(isAuthLoginPath('/api/v1/auth/login?x=1'), true);
      expect(isAuthLoginPath('/api/v1/auth/login/'), true);
      expect(isAuthLoginPath('/api/v1/home/sections'), false);
    });
  });

  group('isSameServerOrigin', () {
    test('true for same scheme+host, false across hosts or on parse failure', () {
      expect(isSameServerOrigin('https://prairie.example', 'https://prairie.example/x'), true);
      expect(isSameServerOrigin('https://prairie.example', 'https://other.example/x'), false);
      expect(isSameServerOrigin(':::', 'https://x'), false);
    });
  });

  group('ApiClient.request', () {
    test('parses error bodies into ApiError', () async {
      final client = _clientWith(
        (_) => jsonResponse('{"message":"bad creds","code":"auth_failed"}', 401, statusMessage: 'Unauthorized'),
      );

      await expectLater(
        client.request<Map<String, dynamic>>(
          const ApiClientOptions(serverUrl: 'https://prairie.example'),
          '/api/v1/auth/login',
          method: 'POST',
          body: '{}',
        ),
        throwsA(
          isA<ApiError>()
              .having((e) => e.message, 'message', 'bad creds')
              .having((e) => e.status, 'status', 401)
              .having((e) => e.code, 'code', 'auth_failed'),
        ),
      );
    });

    test('calls onUnauthorized for 401 on non-login paths', () async {
      var unauthorizedCalls = 0;
      final client = _clientWith((_) => jsonResponse('{"message":"expired"}', 401));

      await expectLater(
        client.request<Map<String, dynamic>>(
          ApiClientOptions(serverUrl: 'https://prairie.example', onUnauthorized: () => unauthorizedCalls++),
          '/api/v1/home/sections',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(unauthorizedCalls, 1);
    });

    test('does not call onUnauthorized for auth/login 401', () async {
      var unauthorizedCalls = 0;
      final client = _clientWith((_) => jsonResponse('{"message":"bad creds"}', 401));

      await expectLater(
        client.request<Map<String, dynamic>>(
          ApiClientOptions(serverUrl: 'https://prairie.example', onUnauthorized: () => unauthorizedCalls++),
          '/api/v1/auth/login',
          method: 'POST',
        ),
        throwsA(isA<ApiError>()),
      );
      expect(unauthorizedCalls, 0);
    });

    test('refreshes the access token and retries once on 401', () async {
      var homeCalls = 0;
      String? authHeaderOnFirstCall;
      String? authHeaderOnRetry;
      String? refreshedAccess;
      String? refreshedRefresh;

      final client = _clientWith((options) {
        if (options.path.endsWith('/api/v1/auth/refresh')) {
          return jsonResponse('{"access_token":"new-tok","refresh_token":"refresh-2","expires_in":3600}', 200);
        }
        homeCalls++;
        final auth = options.headers['Authorization'] as String?;
        if (homeCalls == 1) {
          authHeaderOnFirstCall = auth;
          return jsonResponse('{"message":"expired"}', 401);
        }
        authHeaderOnRetry = auth;
        return jsonResponse('{"ok":true}', 200);
      });

      final result = await client.request<Map<String, dynamic>>(
        ApiClientOptions(
          serverUrl: 'https://prairie.example',
          accessToken: 'old-tok',
          refreshToken: 'refresh-1',
          onTokensRefreshed: (access, refresh) {
            refreshedAccess = access;
            refreshedRefresh = refresh;
          },
        ),
        '/api/v1/home/sections',
      );

      expect(result, {'ok': true});
      expect(authHeaderOnFirstCall, 'Bearer old-tok');
      expect(authHeaderOnRetry, 'Bearer new-tok');
      expect(refreshedAccess, 'new-tok');
      expect(refreshedRefresh, 'refresh-2');
    });

    test('calls onUnauthorized when there is no refresh token', () async {
      var unauthorizedCalls = 0;
      final client = _clientWith((_) => jsonResponse('{"message":"expired"}', 401));

      await expectLater(
        client.request<Map<String, dynamic>>(
          ApiClientOptions(
            serverUrl: 'https://prairie.example',
            accessToken: 'old',
            onUnauthorized: () => unauthorizedCalls++,
          ),
          '/api/v1/home/sections',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(unauthorizedCalls, 1);
    });

    test('calls onUnauthorized when the refresh call itself fails', () async {
      var unauthorizedCalls = 0;
      final client = _clientWith((options) {
        if (options.path.endsWith('/api/v1/auth/refresh')) {
          return jsonResponse('nope', 401);
        }
        return jsonResponse('{"message":"expired"}', 401);
      });

      await expectLater(
        client.request<Map<String, dynamic>>(
          ApiClientOptions(
            serverUrl: 'https://prairie.example',
            accessToken: 'old',
            refreshToken: 'stale',
            onUnauthorized: () => unauthorizedCalls++,
          ),
          '/api/v1/libraries',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
      expect(unauthorizedCalls, 1);
    });

    test('logs out when a refreshed request still returns 401', () async {
      var homeCalls = 0;
      var unauthorizedCalls = 0;
      var tokensRefreshedCalls = 0;

      final client = _clientWith((options) {
        if (options.path.endsWith('/api/v1/auth/refresh')) {
          return jsonResponse('{"access_token":"new","refresh_token":"ref2","expires_in":60}', 200);
        }
        homeCalls++;
        return jsonResponse('{"message":"still bad"}', 401);
      });

      await expectLater(
        client.request<Map<String, dynamic>>(
          ApiClientOptions(
            serverUrl: 'https://prairie.example',
            accessToken: 'old',
            refreshToken: 'ref',
            // Mirrors the TS test's listener/logout handlers throwing —
            // those errors must not mask the resulting ApiError.
            onUnauthorized: () {
              unauthorizedCalls++;
              throw Exception('logout boom');
            },
            onTokensRefreshed: (_, _) {
              tokensRefreshedCalls++;
              throw Exception('listener boom');
            },
          ),
          '/api/v1/home/sections',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401).having((e) => e.message, 'message', 'still bad')),
      );
      expect(homeCalls, 2);
      expect(unauthorizedCalls, 1);
      expect(tokensRefreshedCalls, 1);
    });

    test('calls onUnauthorized for 403 with auth codes, not for ordinary 403', () async {
      var authCodeCalls = 0;
      final authCodeClient = _clientWith((_) => jsonResponse('{"message":"gone","code":"token_expired"}', 403));
      await expectLater(
        authCodeClient.request<Map<String, dynamic>>(
          ApiClientOptions(serverUrl: 'https://prairie.example', onUnauthorized: () => authCodeCalls++),
          '/api/v1/libraries',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 403).having((e) => e.code, 'code', 'token_expired')),
      );
      expect(authCodeCalls, 1);

      var ordinaryCalls = 0;
      final ordinaryClient = _clientWith((_) => jsonResponse('{"message":"nope"}', 403));
      await expectLater(
        ordinaryClient.request<Map<String, dynamic>>(
          ApiClientOptions(serverUrl: 'https://prairie.example', onUnauthorized: () => ordinaryCalls++),
          '/api/v1/libraries',
        ),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)),
      );
      expect(ordinaryCalls, 0);
    });

    test('sends profile headers when provided', () async {
      String? profileIdHeader;
      String? profileTokenHeader;
      final client = _clientWith((options) {
        profileIdHeader = options.headers['X-Profile-Id'] as String?;
        profileTokenHeader = options.headers['X-Profile-Token'] as String?;
        return jsonResponse('{}', 200);
      });

      await client.request<Map<String, dynamic>>(
        const ApiClientOptions(
          serverUrl: 'https://prairie.example',
          accessToken: 'tok',
          profileId: 'profile-1',
          profileToken: 'pin-token',
        ),
        '/api/v1/home/sections',
      );

      expect(profileIdHeader, 'profile-1');
      expect(profileTokenHeader, 'pin-token');
    });

    test('falls back to the "error" field, then the status message, for error text', () async {
      final errorFieldClient = _clientWith((_) => jsonResponse('{"error":"nope"}', 500));
      await expectLater(
        errorFieldClient.request<Map<String, dynamic>>(
          const ApiClientOptions(serverUrl: 'https://prairie.example'),
          '/api/v1/x',
        ),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'nope')),
      );

      final nonJsonClient = _clientWith((_) => jsonResponse('plain', 502, statusMessage: 'Bad'));
      await expectLater(
        nonJsonClient.request<Map<String, dynamic>>(
          const ApiClientOptions(serverUrl: 'https://prairie.example'),
          '/api/v1/x',
        ),
        throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Bad')),
      );
    });

    test('204 responses resolve to null', () async {
      final client = _clientWith((_) => ResponseBody.fromString('', 204));
      final result = await client.request<Map<String, dynamic>?>(
        const ApiClientOptions(serverUrl: 'https://prairie.example'),
        '/api/v1/x',
      );
      expect(result, null);
    });
  });
}
