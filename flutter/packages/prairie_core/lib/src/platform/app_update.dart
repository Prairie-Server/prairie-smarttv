import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A newer GitHub release than the running build.
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.url});

  /// Without the tag's leading `v` (e.g. `0.4.7`).
  final String version;

  /// The release page, where the .tpk / .ipk packages are attached.
  final String url;
}

/// Compares two `X.Y.Z[-pre][+build]` versions (an optional leading `v` is
/// ignored) numerically per part; a pre-release sorts before its release.
/// Returns <0, 0 or >0 like [Comparable.compareTo].
int compareVersions(String a, String b) {
  (List<int>, bool) parse(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final dash = core.indexOf('-');
    final numbers = (dash < 0 ? core : core.substring(0, dash)).split('.');
    return ([for (final n in numbers) int.tryParse(n) ?? 0], dash >= 0);
  }

  final (pa, preA) = parse(a);
  final (pb, preB) = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  if (preA == preB) return 0;
  return preA ? -1 : 1;
}

/// Checks GitHub Releases for a newer sideload package at most once per
/// [interval], caching the answer in shared_preferences — unauthenticated
/// GitHub allows 60 requests/hour per IP, and a household's TVs share one.
/// Every failure is silent: no update notice is ever better than an error.
class AppUpdateChecker {
  AppUpdateChecker({
    required this.prefs,
    required this.dio,
    required this.currentVersion,
    this.interval = const Duration(days: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const latestReleaseUrl = 'https://api.github.com/repos/Prairie-Server/prairie-smarttv/releases/latest';
  static const _checkedAtKey = 'prairie.update.checked_at';
  static const _tagKey = 'prairie.update.latest_tag';
  static const _urlKey = 'prairie.update.latest_url';

  final SharedPreferencesAsync prefs;
  final Dio dio;

  /// The running build's version; empty (unstamped dev build) disables the check.
  final String currentVersion;
  final Duration interval;
  final DateTime Function() _now;

  Future<AvailableUpdate?> check() async {
    if (currentVersion.isEmpty) return null;
    try {
      var tag = await prefs.getString(_tagKey);
      var url = await prefs.getString(_urlKey);
      final checkedAt = await prefs.getInt(_checkedAtKey);
      final now = _now();
      if (checkedAt == null || now.difference(DateTime.fromMillisecondsSinceEpoch(checkedAt)) >= interval) {
        // Stamp the attempt first so a failing request also waits a day.
        await prefs.setInt(_checkedAtKey, now.millisecondsSinceEpoch);
        final latest = await _fetchLatest();
        if (latest != null) {
          (tag, url) = latest;
          await prefs.setString(_tagKey, tag);
          await prefs.setString(_urlKey, url);
        }
      }
      if (tag == null || url == null || compareVersions(tag, currentVersion) <= 0) return null;
      return AvailableUpdate(version: tag.replaceFirst(RegExp(r'^[vV]'), ''), url: url);
    } catch (_) {
      return null;
    }
  }

  Future<(String, String)?> _fetchLatest() async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        latestReleaseUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      return parseLatestRelease(response.data);
    } catch (_) {
      return null;
    }
  }
}

/// (`tag_name`, `html_url`) from a GitHub `releases/latest` body, or null.
(String, String)? parseLatestRelease(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final tag = json['tag_name'];
  final url = json['html_url'];
  if (tag is! String || tag.isEmpty || url is! String || !url.startsWith('https://')) return null;
  return (tag, url);
}
