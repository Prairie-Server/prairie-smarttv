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
}
