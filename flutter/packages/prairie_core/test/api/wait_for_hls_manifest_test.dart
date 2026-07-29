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

    const fmp4Playlist = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10.427,\nseg_00000.m4s\n';

    test('does not report ready on an fMP4 playlist until the init segment is fetchable', () async {
      final adapter = FakeHttpAdapter((options) {
        final path = options.path;
        if (path.endsWith('master.m3u8')) return _plainResponse(fmp4Playlist, 200);
        if (path.endsWith('seg_00000.m4s')) {
          return ResponseBody.fromString('segment', 206);
        }
        if (path.endsWith('init.mp4')) {
          // Init segment isn't written yet — media segment alone must not be enough.
          return ResponseBody.fromString('not found', 404);
        }
        throw StateError('unexpected request: $path');
      });
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
    });

    test('reports ready on an fMP4 playlist once both init and media segments are fetchable', () async {
      final adapter = FakeHttpAdapter((options) {
        final path = options.path;
        if (path.endsWith('master.m3u8')) return _plainResponse(fmp4Playlist, 200);
        if (path.endsWith('seg_00000.m4s')) return ResponseBody.fromString('segment', 206);
        if (path.endsWith('init.mp4')) return ResponseBody.fromString('init', 200);
        throw StateError('unexpected request: $path');
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final ready = await waitForHlsManifest(
        'https://prairie.example/master.m3u8',
        dio: dio,
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 10),
      );

      expect(ready, isTrue);
    });
  });

  group('waitForHlsManifest — master playlist redirection', () {
    const masterPlaylist =
        '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\nmedia.m3u8\n';
    const mediaPlaylist = '#EXTM3U\n#EXTINF:2.0,\nseg_00000.ts\n';

    test('follows a master playlist to the media playlist and reports ready', () async {
      final adapter = FakeHttpAdapter((options) {
        final path = options.path;
        if (path.contains('media.m3u8')) return _plainResponse(mediaPlaylist, 200);
        if (path.contains('master.m3u8')) return _plainResponse(masterPlaylist, 200);
        if (path.contains('seg_00000.ts')) return ResponseBody.fromString('segment', 206);
        throw StateError('unexpected request: $path');
      });
      final dio = Dio()..httpClientAdapter = adapter;

      final ready = await waitForHlsManifest(
        'https://prairie.example/master.m3u8',
        dio: dio,
        timeout: const Duration(seconds: 5),
        interval: const Duration(milliseconds: 10),
      );

      expect(ready, isTrue);
      expect(adapter.requests.any((r) => r.path.contains('media.m3u8')), isTrue);
    });

    test('resolves the variant URI relative to the master and preserves the query string', () {
      expect(
        firstUriLine('https://prairie.example/master.m3u8?st=abc&token=xyz', masterPlaylist),
        'https://prairie.example/media.m3u8?st=abc&token=xyz',
      );
    });

    test('keeps polling (does not crash or report ready) when the master has no URI line yet', () async {
      const emptyMaster = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\n';
      final adapter = FakeHttpAdapter((options) => _plainResponse(emptyMaster, 200));
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

    test('follows the master to a variant at most once, even if that variant also carries STREAM-INF', () async {
      const master = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\nvariant.m3u8\n';
      // Pathological: the followed variant itself carries STREAM-INF pointing
      // further on. Must not be followed a second time.
      const pathologicalVariant = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=8000000\nvariant2.m3u8\n';
      var masterRequests = 0;
      var variantRequests = 0;
      final adapter = FakeHttpAdapter((options) {
        final path = options.path;
        if (path.contains('variant2.m3u8')) throw StateError('must not follow a second variant');
        if (path.contains('variant.m3u8')) {
          variantRequests++;
          return _plainResponse(pathologicalVariant, 200);
        }
        if (path.contains('master.m3u8')) {
          masterRequests++;
          return _plainResponse(master, 200);
        }
        throw StateError('unexpected request: $path');
      });
      final dio = Dio()..httpClientAdapter = adapter;

      await expectLater(
        () => waitForHlsManifest(
          'https://prairie.example/master.m3u8',
          dio: dio,
          timeout: const Duration(milliseconds: 60),
          interval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<TranscodeStartupTimeoutError>()),
      );

      expect(masterRequests, 1);
      expect(variantRequests, greaterThan(1));
    });
  });
}
