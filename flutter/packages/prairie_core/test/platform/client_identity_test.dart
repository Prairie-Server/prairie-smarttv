import 'dart:convert';

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

    test('smartTv factory uses the TV name the owner gave it', () {
      final named = ClientIdentity.smartTv(
        platformLabel: 'webOS',
        devicePlatform: 'webos',
        deviceName: '  Living Room TV ',
      );
      expect(named.deviceName, 'Living Room TV');
    });

    test('smartTv factory falls back when the TV name is missing or blank', () {
      for (final raw in <String?>[null, '', '   ', '\n\t']) {
        final identity = ClientIdentity.smartTv(
          platformLabel: 'Tizen',
          devicePlatform: 'tizen',
          deviceName: raw,
        );
        expect(identity.deviceName, 'Prairie Smart TV (Tizen)', reason: 'raw=$raw');
      }
    });
  });

  group('fitTvDeviceName', () {
    test('returns null for null, empty and whitespace-only names', () {
      expect(fitTvDeviceName(null), isNull);
      expect(fitTvDeviceName(''), isNull);
      expect(fitTvDeviceName(' \t\r\n '), isNull);
    });

    test('trims and collapses whitespace and control characters', () {
      expect(fitTvDeviceName('  Bedroom   TV  '), 'Bedroom TV');
      expect(fitTvDeviceName('Den\r\nTV\u0000x'), 'Den TV x');
    });

    test('keeps names within the byte limit unchanged', () {
      final exact = 'a' * tvDeviceNameMaxBytes;
      expect(fitTvDeviceName(exact), exact);
    });

    test('cuts long ASCII names to the byte limit', () {
      expect(fitTvDeviceName('b' * 100), 'b' * tvDeviceNameMaxBytes);
    });

    test('cuts on a character boundary, never inside a multi-byte character', () {
      // 'é' is 2 UTF-8 bytes: 31 of them fill 62 bytes, the 32nd would overflow.
      final fitted = fitTvDeviceName('é' * 40)!;
      expect(fitted, 'é' * 31);
      expect(utf8.encode(fitted).length, lessThanOrEqualTo(tvDeviceNameMaxBytes));

      // Emoji are 4 bytes (surrogate pairs in Dart): 15 fit in 60 bytes.
      final emoji = fitTvDeviceName('\u{1F4FA}' * 20)!;
      expect(emoji.runes.length, 15);
      expect(utf8.encode(emoji).length, 60);
    });

    test('drops trailing space left by the cut', () {
      final raw = '${'c' * 62} d';
      expect(fitTvDeviceName(raw), 'c' * 62);
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

    test('sends the TV name as the device name header', () async {
      String? seenName;
      final adapter = FakeHttpAdapter((options) {
        seenName = options.headers['X-Prairie-Device-Name']?.toString();
        return jsonResponse('{}', 200);
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final identity = ClientIdentity.smartTv(
        platformLabel: 'webOS',
        devicePlatform: 'webos',
        deviceName: 'Kitchen TV',
      );
      final client = ApiClient(dio: dio, identity: identity);
      await client.request<Map<String, dynamic>>(
        const ApiClientOptions(serverUrl: 'https://prairie.example'),
        '/api/v1/setup/status',
      );

      expect(seenName, 'Kitchen TV');
    });
  });
}
