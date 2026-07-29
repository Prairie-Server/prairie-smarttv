import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import '../api/fake_http_adapter.dart';

void main() {
  group('ClientIdentity', () {
    test('default avoids Dart/x.y and matches TS update-check UA', () {
      const identity = ClientIdentity();
      expect(identity.userAgent, 'Prairie-SmartTV');
      expect(identity.userAgent, isNot(contains('Dart/')));
      expect(identity.devicePlatform, 'smarttv');
      expect(identity.deviceName, 'Prairie Smart TV');
    });

    test('smartTv factory embeds platform label and version', () {
      final tizen = ClientIdentity.smartTv(platformLabel: 'Tizen', devicePlatform: 'tizen');
      expect(tizen.userAgent, 'Prairie-SmartTV/1.0.0 (Tizen; Flutter)');
      expect(tizen.devicePlatform, 'tizen');
      expect(tizen.deviceName, 'Prairie Smart TV (Tizen)');

      final webos = ClientIdentity.smartTv(platformLabel: 'webOS', devicePlatform: 'webos', version: '2.1.0');
      expect(webos.userAgent, 'Prairie-SmartTV/2.1.0 (webOS; Flutter)');
      expect(webos.devicePlatform, 'webos');
    });
  });

  group('ApiClient User-Agent', () {
    test('sends Prairie User-Agent and device headers on every request', () async {
      String? seenUa;
      String? seenPlatform;
      String? seenName;
      final adapter = FakeHttpAdapter((options) {
        seenUa = options.headers['User-Agent']?.toString() ?? options.headers['user-agent']?.toString();
        seenPlatform = options.headers['X-Prairie-Device-Platform']?.toString();
        seenName = options.headers['X-Prairie-Device-Name']?.toString();
        return jsonResponse('{}', 200);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final identity = ClientIdentity.smartTv(platformLabel: 'Tizen', devicePlatform: 'tizen');
      final client = ApiClient(dio: dio, identity: identity);
      await client.request<Map<String, dynamic>>(
        const ApiClientOptions(serverUrl: 'https://prairie.example'),
        '/api/v1/setup/status',
      );

      expect(seenUa, identity.userAgent);
      expect(seenUa, isNot(contains('Dart/')));
      expect(seenPlatform, 'tizen');
      expect(seenName, 'Prairie Smart TV (Tizen)');
    });
  });
}
