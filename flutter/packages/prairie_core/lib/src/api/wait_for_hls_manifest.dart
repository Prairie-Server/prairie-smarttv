import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

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

/// Resolve the first media segment URI from an m3u8 body relative to [playlistUrl].
String? firstMediaSegmentUrl(String playlistUrl, String body) {
  for (final rawLine in body.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    try {
      final base = Uri.parse(playlistUrl);
      final resolved = base.resolve(line);
      if (resolved.query.isEmpty && base.query.isNotEmpty) {
        return resolved.replace(query: base.query).toString();
      }
      return resolved.toString();
    } catch (_) {
      return null;
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

    final body = await _fetchText(client, url, cancelToken);
    if (cancelToken?.isCancelled == true) return false;

    if (body != null && body.contains('#EXTM3U')) {
      if (!requireSegment) return true;
      if (body.contains('#EXTINF')) {
        final segmentUrl = firstMediaSegmentUrl(url, body);
        if (segmentUrl != null) {
          final ready = await _segmentReady(client, segmentUrl, cancelToken);
          if (cancelToken?.isCancelled == true) return false;
          if (ready) return true;
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
      developer.log('HLS playlist not found yet (404): $url', name: 'prairie.hls_probe');
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
