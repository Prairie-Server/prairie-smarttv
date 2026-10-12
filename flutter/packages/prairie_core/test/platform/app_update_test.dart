import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/fake_http_adapter.dart';
import '../test_shared_preferences.dart';

void main() {
  group('compareVersions', () {
    test('compares numerically, not as strings', () {
      expect(compareVersions('0.4.10', '0.4.9'), greaterThan(0));
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });

    test('ignores a leading v and build metadata', () {
      expect(compareVersions('v0.4.6', '0.4.6'), 0);
      expect(compareVersions('0.4.6+3', 'v0.4.6'), 0);
      expect(compareVersions('v0.4.7', '0.4.6'), greaterThan(0));
    });

    test('treats missing parts as zero and sorts pre-releases first', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('0.5.0-rc.1', '0.5.0'), lessThan(0));
      expect(compareVersions('0.5.0-rc.1', '0.4.9'), greaterThan(0));
    });
  });

  group('parseLatestRelease', () {
    test('reads tag_name and html_url', () {
      expect(
        parseLatestRelease({'tag_name': 'v0.4.7', 'html_url': 'https://github.com/x/y/releases/tag/v0.4.7'}),
        ('v0.4.7', 'https://github.com/x/y/releases/tag/v0.4.7'),
      );
    });

    test('rejects malformed bodies', () {
      expect(parseLatestRelease(null), isNull);
      expect(parseLatestRelease('nope'), isNull);
      expect(parseLatestRelease({'tag_name': 'v1.0.0'}), isNull);
      expect(parseLatestRelease({'tag_name': '', 'html_url': 'https://x'}), isNull);
      expect(parseLatestRelease({'tag_name': 'v1', 'html_url': 'javascript:alert(1)'}), isNull);
    });
  });

  group('AppUpdateChecker', () {
    late FakeHttpAdapter adapter;
    late DateTime now;
    var tag = 'v0.5.0';

    AppUpdateChecker checker({String current = '0.4.6'}) => AppUpdateChecker(
      prefs: SharedPreferencesAsync(),
      dio: Dio()..httpClientAdapter = adapter,
      currentVersion: current,
      now: () => now,
    );

    setUp(() {
      installInMemorySharedPreferences();
      now = DateTime(2026, 10, 12, 9);
      tag = 'v0.5.0';
      adapter = FakeHttpAdapter(
        (_) => jsonResponse('{"tag_name":"$tag","html_url":"https://github.com/r/releases/tag/$tag"}', 200),
      );
    });

    test('reports a newer release', () async {
      final update = await checker().check();
      expect(update?.version, '0.5.0');
      expect(update?.url, 'https://github.com/r/releases/tag/v0.5.0');
    });

    test('reports nothing when current is up to date', () async {
      expect(await checker(current: '0.5.0').check(), isNull);
    });

    test('hits GitHub at most once a day and serves the cache in between', () async {
      await checker().check();
      now = now.add(const Duration(hours: 23));
      tag = 'v0.6.0';
      expect((await checker().check())?.version, '0.5.0');
      expect(adapter.callCount, 1);

      now = now.add(const Duration(hours: 1));
      expect((await checker().check())?.version, '0.6.0');
      expect(adapter.callCount, 2);
    });

    test('a failed request is silent and still waits a day', () async {
      adapter = FakeHttpAdapter((_) => jsonResponse('{"message":"rate limited"}', 403));
      expect(await checker().check(), isNull);
      expect(await checker().check(), isNull);
      expect(adapter.callCount, 1);
    });

    test('an unstamped build never checks', () async {
      expect(await checker(current: '').check(), isNull);
      expect(adapter.callCount, 0);
    });
  });
}
