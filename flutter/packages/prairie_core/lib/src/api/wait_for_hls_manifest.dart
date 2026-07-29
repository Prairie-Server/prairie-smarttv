import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Thrown when the HLS playlist never becomes playable before the deadline.
/// Mirrors `TranscodeStartupTimeoutError`.
class TranscodeStartupTimeoutError implements Exception {
  TranscodeStartupTimeoutError([this.message = 'Transcode timed out']);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when the readiness probe gets a 401/403 back. Unlike a 404/5xx,
/// this can never resolve by waiting longer, so it must not be swallowed
/// into the same "not ready yet" bucket that drives the poll/backoff loop.
class HlsProbeAuthError implements Exception {
  HlsProbeAuthError(this.statusCode, [this.message = 'Not authorized to fetch HLS playlist']);
  final int statusCode;
  final String message;

  @override
  String toString() => '$message (HTTP $statusCode)';
}

/// Resolves [reference] relative to [playlistUrl], carrying the playlist's
/// own query (session auth) forward when the reference doesn't have one of
/// its own — relative HLS URIs never repeat the parent's query string.
String? _resolveHlsReference(String playlistUrl, String reference) {
  try {
    final base = Uri.parse(playlistUrl);
    final resolved = base.resolve(reference);
    if (resolved.query.isEmpty && base.query.isNotEmpty) {
      return resolved.replace(query: base.query).toString();
    }
    return resolved.toString();
  } catch (_) {
    return null;
  }
}

/// Resolve the first non-comment URI line in an m3u8 body relative to
/// [playlistUrl] — the first media segment in a media playlist, or the
/// variant URI in a master playlist (`#EXT-X-STREAM-INF` is always followed
/// by exactly one URI line, same shape as a segment reference).
String? firstUriLine(String playlistUrl, String body) {
  for (final rawLine in body.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    return _resolveHlsReference(playlistUrl, line);
  }
  return null;
}

/// Resolve the first media segment URI from an m3u8 body relative to [playlistUrl].
String? firstMediaSegmentUrl(String playlistUrl, String body) => firstUriLine(playlistUrl, body);

/// Resolve the fMP4 init segment (`#EXT-X-MAP:URI="…"`) relative to
/// [playlistUrl], if the playlist declares one. Media segments in an fMP4
/// playlist are unplayable without it — a readiness probe that only checks
/// the first `#EXTINF` segment reports "ready" without confirming the init
/// segment is actually fetchable.
String? initSegmentUrl(String playlistUrl, String body) {
  final mapLine = RegExp(r'#EXT-X-MAP:.*URI="([^"]+)"');
  for (final rawLine in body.split('\n')) {
    final line = rawLine.trim();
    final match = mapLine.firstMatch(line);
    if (match != null) {
      return _resolveHlsReference(playlistUrl, match.group(1)!);
    }
  }
  return null;
}

bool isHlsUrl(String url) {
  final path = url.split('?').first.toLowerCase();
  return path.endsWith('.m3u8') || path.contains('/hls') || path.contains('master.m3u8');
}

/// Poll until an HLS playlist is playable: `#EXTM3U` present and (optionally)
/// the first media segment is fetchable. Opening AVPlay/PlusPlayer on a
/// not-yet-written remux/transcode pipeline fails with
/// "streaming connection timed out".
Future<bool> waitForHlsManifest(
  String url, {
  Dio? dio,
  Duration interval = const Duration(milliseconds: 500),
  Duration timeout = const Duration(seconds: 90),
  bool requireSegment = true,
  bool throwOnTimeout = true,
  Duration keepAliveEvery = const Duration(seconds: 10),
  FutureOr<void> Function()? onKeepAlive,
  CancelToken? cancelToken,
}) async {
  final client = dio ?? Dio();
  final deadline = DateTime.now().add(timeout);
  var delay = interval;
  var nextKeepAliveAt = DateTime.now();
  var probeUrl = url; // the master; AVPlay/attach() keeps the original `url`
  var followedVariant = false;

  while (DateTime.now().isBefore(deadline)) {
    if (cancelToken?.isCancelled == true) return false;

    if (onKeepAlive != null && !DateTime.now().isBefore(nextKeepAliveAt)) {
      try {
        await onKeepAlive();
      } catch (_) {
        // Keepalive is best-effort.
      }
      if (cancelToken?.isCancelled == true) return false;
      nextKeepAliveAt = DateTime.now().add(keepAliveEvery);
    }

    final body = await _fetchText(client, probeUrl, cancelToken);
    if (cancelToken?.isCancelled == true) return false;

    if (body != null && body.contains('#EXTM3U')) {
      // A master playlist carries #EXT-X-STREAM-INF and a variant URI, never
      // #EXTINF. Follow it once and poll the media playlist from here on: the
      // master is static, the media playlist is the one that grows.
      if (!followedVariant && body.contains('#EXT-X-STREAM-INF')) {
        final variant = firstUriLine(probeUrl, body);
        if (variant != null) {
          probeUrl = variant;
          followedVariant = true;
          continue; // re-probe immediately, don't burn a backoff tick
        }
        // No URI line yet — fall through to the normal backoff and retry.
      }
      if (!requireSegment) return true;
      if (body.contains('#EXTINF')) {
        final initUrl = initSegmentUrl(probeUrl, body);
        final initReady = initUrl == null || await _segmentReady(client, initUrl, cancelToken);
        if (cancelToken?.isCancelled == true) return false;

        if (initReady) {
          final segmentUrl = firstUriLine(probeUrl, body);
          if (segmentUrl != null) {
            final ready = await _segmentReady(client, segmentUrl, cancelToken);
            if (cancelToken?.isCancelled == true) return false;
            if (ready) return true;
          }
        }
      }
    }

    await Future<void>.delayed(delay);
    if (cancelToken?.isCancelled == true) return false;
    final nextMs = (delay.inMilliseconds * 1.5).round().clamp(interval.inMilliseconds, 4000);
    delay = Duration(milliseconds: nextMs);
  }

  if (throwOnTimeout) throw TranscodeStartupTimeoutError();
  return false;
}

/// Fetches [url] for the readiness poll. Returns the body when ready, `null`
/// when the playlist genuinely isn't written yet (404/5xx/transport error —
/// worth retrying), and throws [HlsProbeAuthError] on 401/403, which is a
/// permanent rejection no amount of polling will resolve.
Future<String?> _fetchText(Dio dio, String url, CancelToken? cancelToken) async {
  Response<String>? response;
  try {
    response = await dio.get<String>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );
  } catch (_) {
    return null;
  }

  final status = response.statusCode;
  if (status == 401 || status == 403) throw HlsProbeAuthError(status!);
  if (status == null || status >= 400) {
    if (status == 404) {
      debugPrint('prairie.hls_probe: HLS playlist not found yet (404): $url');
    }
    return null;
  }
  return response.data;
}

Future<bool> _segmentReady(Dio dio, String url, CancelToken? cancelToken) async {
  try {
    var response = await dio.head<void>(
      url,
      cancelToken: cancelToken,
      options: Options(
        receiveTimeout: const Duration(seconds: 12),
        sendTimeout: const Duration(seconds: 12),
        validateStatus: (_) => true,
      ),
    );
    if (response.statusCode == 405 || response.statusCode == 501) {
      response = await dio.get<void>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: {'Range': 'bytes=0-0'},
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 12),
          validateStatus: (_) => true,
        ),
      );
    }
    final status = response.statusCode ?? 0;
    return status >= 200 && status < 300;
  } catch (_) {
    return false;
  }
}
