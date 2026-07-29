import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import '../api/fake_http_adapter.dart';

ApiClient _clientWith(ResponseBody Function(RequestOptions) handler) {
  final dio = Dio()..httpClientAdapter = FakeHttpAdapter(handler);
  return ApiClient(dio: dio);
}

void main() {
  group('verifyProfilePin', () {
    test('posts pin and parses profile_token', () async {
      late RequestOptions seen;
      final client = _clientWith((options) {
        seen = options;
        return jsonResponse(
          '{"valid":true,"profile_token":"ptok","expires_at":"2099-01-01T00:00:00Z"}',
          200,
        );
      });

      final result = await verifyProfilePin(
        client,
        'https://prairie.example.com',
        'access',
        'profile/with spaces',
        '1234',
      );

      expect(result.valid, isTrue);
      expect(result.profileToken, 'ptok');
      expect(seen.method, 'POST');
      expect(seen.path, contains('/api/v1/profiles/'));
      expect(seen.path, contains(Uri.encodeComponent('profile/with spaces')));
      expect(seen.path, endsWith('/verify-pin'));
      expect(seen.data, {'pin': '1234'});
    });

    test('parses invalid pin responses', () async {
      final client = _clientWith((_) => jsonResponse('{"valid":false}', 200));
      final result = await verifyProfilePin(
        client,
        'https://prairie.example.com',
        'access',
        'p1',
        '0000',
      );
      expect(result.valid, isFalse);
      expect(result.profileToken, isNull);
    });
  });

  group('pickDefaultProfile', () {
    test('prefers primary then first', () {
      expect(pickDefaultProfile([]), isNull);
      expect(
        pickDefaultProfile([
          const Profile(id: 'a', name: 'A', isPrimary: false, isChild: false),
          const Profile(id: 'b', name: 'B', isPrimary: true, isChild: false),
        ])?.id,
        'b',
      );
      expect(
        pickDefaultProfile([
          const Profile(id: 'a', name: 'A', isPrimary: false, isChild: false),
        ])?.id,
        'a',
      );
    });
  });
}
