import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';

import 'fake_http_adapter.dart';

void main() {
  setUp(resetQualityLadderCache);

  const session = PrairieSession(
    serverUrl: 'https://prairie.example',
    username: 'u',
    profileId: 'p',
    accessToken: 'tok',
  );

  group('isValidQualityLadder', () {
    test('rejects empty or incomplete rungs (all-or-nothing)', () {
      expect(isValidQualityLadder(const []), isFalse);
      expect(
        isValidQualityLadder(const [
          QualityLadderRung(id: '1080p', label: '1080p', resolution: '1080p', height: 1080, bitrateKbps: 6000),
          QualityLadderRung(id: '720p', label: '720p', resolution: '720p', height: 720, bitrateKbps: 0),
        ]),
        isFalse,
      );
    });

    test('accepts a fully populated ladder', () {
      expect(isValidQualityLadder(fallbackQualityLadder), isTrue);
    });
  });

  group('qualityLadderForSourceHeight', () {
    test('omits upscales and keeps a native-height rung', () {
      final capped = qualityLadderForSourceHeight(fallbackQualityLadder, 1080);
      expect(capped.first.id, '1080p-high');
      expect(capped.any((r) => r.id == '2160p'), isFalse);
      expect(capped.any((r) => r.id == '1080p'), isTrue);
    });

    test('full ladder when source height is unknown', () {
      expect(qualityLadderForSourceHeight(fallbackQualityLadder, 0), hasLength(fallbackQualityLadder.length));
    });
  });

  group('buildQualityOptions', () {
    test('leads with auto and original, then rungs below native', () {
      final options = buildQualityOptions(
        ladder: fallbackQualityLadder,
        nativeHeight: 1080,
        playMethod: 'direct',
        sourceResolutionLabel: '1080p',
        modes: defaultQualityModes,
      );
      expect(options.map((o) => o.id).take(2), ['auto', 'original']);
      expect(options.any((o) => o.id == '1080p'), isFalse);
      expect(options.any((o) => o.id == '720p-high'), isTrue);
      expect(options.any((o) => o.id == '720p'), isTrue);
    });

    test('keys options on rung id so high variants stay distinct', () {
      final options = buildQualityOptions(
        ladder: fallbackQualityLadder,
        nativeHeight: 2160,
      );
      final ids = options.map((o) => o.id).toList();
      expect(ids, containsAll(['1080p-high', '1080p']));
    });
  });

  group('fetchQualityLadder', () {
    test('serves the server ladder once loaded', () async {
      final adapter = FakeHttpAdapter((options) {
        expect(options.uri.path, contains('/api/v1/playback/quality-ladder'));
        return jsonResponse(
          '{"rungs":[{"id":"540p","label":"540p","resolution":"540p","height":540,"bitrate_kbps":1800}],"modes":["auto","original"]}',
          200,
        );
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

      final ladder = await fetchQualityLadder(client, session);
      expect(ladder.map((r) => r.id), ['540p']);
      expect(ladder.single.bitrateKbps, 1800);
    });

    test('falls back when the request fails and does not cache the failure', () async {
      var calls = 0;
      final adapter = FakeHttpAdapter((options) {
        calls++;
        if (calls == 1) {
          return jsonResponse('{"error":"offline"}', 500);
        }
        return jsonResponse(
          '{"rungs":[{"id":"480p","label":"480p","resolution":"480p","height":480,"bitrate_kbps":1500}],"modes":["auto"]}',
          200,
        );
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

      final first = await fetchQualityLadder(client, session);
      expect(first.any((r) => r.id == '1080p'), isTrue);

      resetQualityLadderCache();
      final second = await fetchQualityLadder(client, session);
      expect(second.map((r) => r.id), ['480p']);
      expect(calls, 2);
    });

    test('falls back on malformed ladders without caching them', () async {
      var calls = 0;
      final adapter = FakeHttpAdapter((options) {
        calls++;
        if (calls == 1) {
          return jsonResponse('{"rungs":[],"modes":[]}', 200);
        }
        return jsonResponse(
          '{"rungs":[{"id":"720p","label":"720p","resolution":"720p","height":720,"bitrate_kbps":2000}],"modes":["auto"]}',
          200,
        );
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

      final first = await fetchQualityLadder(client, session);
      expect(first.length, greaterThan(2));

      resetQualityLadderCache();
      final second = await fetchQualityLadder(client, session);
      expect(second.map((r) => r.id), ['720p']);
    });

    test('caches a valid ladder across calls', () async {
      var calls = 0;
      final adapter = FakeHttpAdapter((options) {
        calls++;
        return jsonResponse(
          '{"rungs":[{"id":"720p","label":"720p","resolution":"720p","height":720,"bitrate_kbps":2000}],"modes":["auto"]}',
          200,
        );
      });
      final client = ApiClient(dio: Dio()..httpClientAdapter = adapter);

      await fetchQualityLadder(client, session);
      await fetchQualityLadder(client, session);
      expect(calls, 1);
    });

    test('never returns an empty ladder', () {
      expect(cachedOrFallbackQualityLadder(), isNotEmpty);
    });
  });

  group('resolveQualityTargets', () {
    test('maps rung ids to resolution + bitrate from the ladder', () {
      final options = buildQualityOptions(ladder: fallbackQualityLadder, nativeHeight: 2160);
      final targets = resolveQualityTargets(
        qualityId: '1080p-high',
        options: options,
        playMethod: 'direct',
        ladder: fallbackQualityLadder,
      );
      expect(targets?.resolution, '1080p');
      expect(targets?.bitrateKbps, 10000);
      expect(targets?.copyVideo, isFalse);
    });

    test('original on direct returns null (drop HLS)', () {
      final targets = resolveQualityTargets(
        qualityId: 'original',
        options: const [],
        playMethod: 'direct',
        ladder: fallbackQualityLadder,
      );
      expect(targets, isNull);
    });
  });
}
