import 'package:dio/dio.dart';

import '../models/auth.dart';
import 'api_client.dart';
import 'playback_session_api.dart';
import 'wait_for_hls_manifest.dart';

export 'wait_for_hls_manifest.dart' show HlsProbeAuthError, TranscodeStartupTimeoutError, isHlsUrl, waitForHlsManifest;

/// Only a genuine re-encode streams over HLS; `direct` and `remux` play the
/// plan's `stream.url` progressive. Used to arm HLS stall detection.
bool needsHlsBootstrap(String? playMethod) {
  return (playMethod ?? '').trim().toLowerCase() == 'transcode';
}

class PreparedPlayback {
  const PreparedPlayback({
    required this.session,
    required this.streamUrl,
    required this.playerStartSeconds,
    required this.streamOriginSeconds,
  });

  final PlaybackSessionResponse session;
  final String streamUrl;
  final double playerStartSeconds;
  final double streamOriginSeconds;
}

const transcodeStartupTimeout = Duration(seconds: 90);

/// Where a protocol-v3 plan starts, read from the plan's `timeline` (the
/// server-anchored source of truth) rather than from the position the client
/// asked for: the server may land on a keyframe/segment before it, and the
/// seek is already baked into `stream.url`.
///
/// - [PreparedPlayback.streamOriginSeconds] is the media time of the
///   player's t=0 (`timeline_offset_seconds`).
/// - [PreparedPlayback.playerStartSeconds] is where the native player seeks
///   after initialize (`player_start_seconds`, in player time). Direct play
///   resumes through this.
///
/// One TV platform limit: progressive remux (`server_remux_progressive`) is
/// a live ffmpeg pipe with no Range support, and the native player rejects
/// `seekTo` on it outright (`PlatformException(SeekTo, Player seek to
/// failed)` on videohole), so its player start is forced to 0 — playback
/// begins at the resolved keyframe (`stream_origin_seconds`), at most a few
/// seconds before the requested position — and every later remux seek is a
/// `seek_reanchor` replan instead of a native seek.
///
/// [fallbackSeekSeconds] only applies to a plan without a timeline.
({double playerStartSeconds, double streamOriginSeconds}) protocolV3StartOffsets(
  PlaybackSessionResponse decision, {
  double fallbackSeekSeconds = 0,
}) {
  final isProgressiveRemux = decision.playMethod.toLowerCase() == 'remux';
  final timeline = decision.timeline;
  if (timeline == null) {
    final seek = fallbackSeekSeconds.isFinite && fallbackSeekSeconds > 0 ? fallbackSeekSeconds : 0.0;
    return (playerStartSeconds: isProgressiveRemux ? 0.0 : seek, streamOriginSeconds: 0.0);
  }
  return (
    playerStartSeconds: isProgressiveRemux ? 0.0 : timeline.playerStartSeconds,
    streamOriginSeconds: timeline.timelineOffsetSeconds,
  );
}

/// Prepares a protocol-v3 plan for the native player.
///
/// The plan's `stream.url` is opaque and authoritative: it is server-anchored
/// (the seek position is baked in) and signed over its complete query, so it
/// is only joined to the server origin — never re-encoded, never given a
/// `seek=` of its own (a rewritten query fails the signature). Positions come
/// from the plan timeline via [protocolV3StartOffsets]; [seekSeconds] is only
/// the fallback for a plan without one.
///
/// HLS still resolves master → variant (videohole cannot pick a variant from
/// a master playlist) and waits for the first segment.
Future<PreparedPlayback> prepareProtocolV3Decision(
  ApiClient client,
  PrairieSession session,
  PlaybackSessionResponse decision,
  double seekSeconds, {
  CancelToken? cancelToken,
}) async {
  final streamType = decision.playbackInfo?.streamType?.toLowerCase() ?? '';
  final isHls = streamType == 'hls' || decision.streamUrl.toLowerCase().contains('.m3u8');
  final streamUrl = resolvePlaybackStreamUrl(session.serverUrl, decision, session.accessToken);
  final offsets = protocolV3StartOffsets(decision, fallbackSeekSeconds: seekSeconds);
  if (!isHls) {
    return PreparedPlayback(
      session: decision,
      streamUrl: streamUrl,
      playerStartSeconds: offsets.playerStartSeconds,
      streamOriginSeconds: offsets.streamOriginSeconds,
    );
  }

  final mediaPosition = offsets.streamOriginSeconds + offsets.playerStartSeconds;
  final probe = await waitForHlsManifest(
    streamUrl,
    dio: client.dio,
    timeout: transcodeStartupTimeout,
    requireSegment: true,
    throwOnTimeout: true,
    keepAliveEvery: const Duration(seconds: 10),
    cancelToken: cancelToken,
    onKeepAlive: () => reportPlaybackProgress(client, session, decision.sessionId, mediaPosition, true),
  );
  return PreparedPlayback(
    session: decision,
    streamUrl: probe.resolvedUrl,
    playerStartSeconds: offsets.playerStartSeconds,
    streamOriginSeconds: offsets.streamOriginSeconds,
  );
}
