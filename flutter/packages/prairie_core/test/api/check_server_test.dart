import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

void main() {
  group('checkServer', () {
    test('accepts a native v2 Prairie server', () async {
      final client = _clientWith((o) {
        if (o.path.endsWith('/api/v2/system/setup')) {
          return jsonResponse('{"needs_setup":false,"wizard_completed":true}', 200);
        }
        return jsonResponse('{"status":"ok","server_name":"Home"}', 200);
      });
      final result = await checkServer(client, 'https://prairie.example.com');
      expect(result, isA<CheckServerSuccess>());
      expect((result as CheckServerSuccess).serverName, 'Home');
      expect(result.needsSetup, isFalse);
    });

    test('falls back to the v1 setup route', () async {
      final client = _clientWith((o) {
        if (o.path.endsWith('/api/v1/auth/setup')) return jsonResponse('{"needs_setup":true}', 200);
        return jsonResponse('{"error":"not found"}', 404);
      });
      final result = await checkServer(client, 'https://prairie.example.com');
      expect(result, isA<CheckServerSuccess>());
      expect((result as CheckServerSuccess).needsSetup, isTrue);
    });

    test('rejects a non-Prairie server where both setup routes 404', () async {
      final client = _clientWith((_) => jsonResponse('{"error":"Not Found"}', 404));
      final result = await checkServer(client, 'https://jellyfin.example.com');
      expect(result, isA<CheckServerFailure>());
      expect((result as CheckServerFailure).message, contains('not a Prairie server'));
    });

    test('rejects a 200 response without a setup payload', () async {
      final client = _clientWith((_) => jsonResponse('{"hello":"world"}', 200));
      final result = await checkServer(client, 'https://other.example.com');
      expect(result, isA<CheckServerFailure>());
      expect((result as CheckServerFailure).message, contains('not a Prairie server'));
    });
  });

  group('probe wording (Apple TV, Android #758/#771)', () {
    test('a bare HTTP error says it could not reach a Prairie server', () async {
      final client = _clientWith((_) => jsonResponse('', 502, statusMessage: 'Bad Gateway'));
      final result = await checkServerCandidates(client, ['https://a.example.com', 'http://a.example.com']);
      expect((result as CheckServerFailure).message, 'Could not reach a Prairie server at that address.');
    });

    test('a bare 404 says it could not reach a Prairie server', () async {
      final client = _clientWith((_) => jsonResponse('', 404, statusMessage: 'Not Found'));
      final result = await checkServer(client, 'https://a.example.com');
      expect((result as CheckServerFailure).message, 'Could not reach a Prairie server at that address.');
    });

    test("an HTTP error keeps the server's message", () async {
      final client = _clientWith((_) => jsonResponse('{"message":"Maintenance"}', 503));
      final result = await checkServer(client, 'https://a.example.com');
      expect((result as CheckServerFailure).message, 'Could not reach server: Maintenance');
    });

    test('a transport failure says it could not reach a Prairie server', () async {
      final client = _clientWith((o) => throw DioException.connectionError(requestOptions: o, reason: 'refused'));
      final result = await checkServer(client, 'https://a.example.com');
      expect((result as CheckServerFailure).message, 'Could not reach a Prairie server at that address.');
    });
  });
}
