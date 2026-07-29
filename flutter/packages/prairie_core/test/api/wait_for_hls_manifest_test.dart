import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

ResponseBody _plainResponse(String body, int statusCode) => ResponseBody.fromString(
  body,
  statusCode,
  headers: {
    Headers.contentTypeHeader: ['text/plain'],
  },
);

void main() {
  group('waitForHlsManifest', () {
    test('throws HlsProbeAuthError immediately on 401 instead of polling to timeout', () async {
      final adapter = FakeHttpAdapter((options) => _plainResponse('unauthorized', 401));
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        () => waitForHlsManifest(
          'https://prairie.example/master.m3u8',
          dio: dio,
          timeout: const Duration(seconds: 5),
          interval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<HlsProbeAuthError>()),
      );

      expect(adapter.callCount, 1);
    });

    test('throws HlsProbeAuthError immediately on 403', () async {
      final adapter = FakeHttpAdapter((options) => _plainResponse('forbidden', 403));
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        () => waitForHlsManifest(
          'https://prairie.example/master.m3u8',
          dio: dio,
          timeout: const Duration(seconds: 5),
          interval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<HlsProbeAuthError>()),
      );

      expect(adapter.callCount, 1);
    });

    test('keeps retrying through 404s until the deadline, then times out normally', () async {
      final adapter = FakeHttpAdapter((options) => _plainResponse('not found', 404));
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        () => waitForHlsManifest(
          'https://prairie.example/master.m3u8',
          dio: dio,
          timeout: const Duration(milliseconds: 50),
          interval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TranscodeStartupTimeoutError>()),
      );

      expect(adapter.callCount, greaterThan(1));
    });
  });
}
