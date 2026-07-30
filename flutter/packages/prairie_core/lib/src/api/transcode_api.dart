import 'package:dio/dio.dart';

import '../models/auth.dart';
import 'api_client.dart';
import 'playback_session_api.dart';
import 'target_resolution.dart';
import 'wait_for_hls_manifest.dart';

export 'wait_for_hls_manifest.dart' show HlsProbeAuthError, TranscodeStartupTimeoutError, isHlsUrl, waitForHlsManifest;

/// Only a genuine re-encode needs the HLS transport. `remux` (video copy,
/// optional audio re-encode) and `direct` both get `stream_url` verbatim from
/// `/playback/start` and play progressive — no `/playback/transcode/start`,
/// no demuxer, no manifest. See [preparePlayableSession].
bool needsHlsBootstrap(String? playMethod) {
  return (playMethod ?? '').trim().toLowerCase() == 'transcode';
}

class TranscodeStartInput {
  const TranscodeStartInput({
    required this.sessionId,
    required this.seekSeconds,
    required this.playMethod,
    this.transcodeAudio = false,
    this.sourceResolution,
    this.maxResolution,
    this.targetResolution,
    this.targetBitrateKbps,
    this.copyVideo = false,
  });

  final String sessionId;
  final double seekSeconds;
  final String playMethod;
  final bool transcodeAudio;
  final String? sourceResolution;
  final String? maxResolution;

  /// Explicit ladder targets. When set, these win over [sourceResolution] /
  /// [maxResolution] / the hardcoded bitrate table — quality switches must
  /// send the server's rung values so High variants stay distinct.
  final String? targetResolution;
  final int? targetBitrateKbps;
  final bool copyVideo;
}

Map<String, dynamic> buildTranscodeStartRequest(TranscodeStartInput input) {
  final isRemux = input.playMethod.trim().toLowerCase() == 'remux';
  final remuxAudio = input.transcodeAudio ? 'aac' : 'copy';
  final copyVideo = input.copyVideo || isRemux;
  final targetResolution = input.targetResolution ??
      (copyVideo ? '' : resolveTargetResolution(input.sourceResolution, input.maxResolution));
  final targetBitrate = input.targetBitrateKbps ??
      (copyVideo ? 0 : targetBitrateKbpsForResolution(targetResolution));
  return {
    'session_id': input.sessionId,
    'seek_seconds': input.seekSeconds < 0 ? 0 : input.seekSeconds,
    'target_resolution': targetResolution,
    if (copyVideo) 'target_codec_video': 'copy',
    // Omit target_codec_video on encode so the server picks the best of
    // client ∩ encodable (av1 → hevc → h264). Smart TV usually lands on hevc.
    'target_codec_audio': copyVideo && isRemux ? remuxAudio : 'aac',
    'target_bitrate_kbps': targetBitrate,
    'segment_duration': 2,
    'subtitle_track_index': -1,
    'subtitle_burn_in': false,
  };
}

class TranscodeStartResponse {
  const TranscodeStartResponse({
    required this.sessionId,
    required this.manifestUrl,
    this.durationSeconds,
    this.playerStartSeconds,
    this.streamOriginSeconds,
    this.canSeekAnywhere,
  });

  final String sessionId;
  final String manifestUrl;
  final double? durationSeconds;
  final double? playerStartSeconds;
  final double? streamOriginSeconds;
  final bool? canSeekAnywhere;

  factory TranscodeStartResponse.fromJson(Map<String, dynamic> json) => TranscodeStartResponse(
    sessionId: json['session_id'] as String? ?? '',
    manifestUrl: json['manifest_url'] as String,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    playerStartSeconds: (json['player_start_seconds'] as num?)?.toDouble(),
    streamOriginSeconds: (json['stream_origin_seconds'] as num?)?.toDouble(),
    canSeekAnywhere: json['can_seek_anywhere'] as bool?,
  );
}

Future<TranscodeStartResponse> startTranscode(
  ApiClient client,
  PrairieSession session,
  Map<String, dynamic> body,
) async {
  final json = await client.request<Map<String, dynamic>>(
    ApiClientOptions(
      serverUrl: session.serverUrl,
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
      profileId: session.profileId,
      profileToken: session.profileToken,
    ),
    '/api/v1/playback/transcode/start',
    method: 'POST',
    body: body,
  );
  return TranscodeStartResponse.fromJson(json);
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

/// `direct` and `remux` play `stream_url` from `/playback/start` verbatim,
/// progressive, over plain HTTP — no `/playback/transcode/start`, no HLS
/// demuxer, no manifest. `remux` still gets its audio re-encoded server-side
/// (ServeRemux acts on `transcode_audio` from the original `/playback/start`
/// response) despite the video being a straight copy; that's the server's
/// concern, not the client's — it never calls the transcode endpoint either
/// way. Only `transcode` (genuine re-encode) needs the HLS transport and
/// waits for the first segment to exist so the native player doesn't time out.
///
/// `direct` and `remux` diverge on how [seekSeconds] gets applied, because
/// only `direct` serves a real, complete, Range-seekable file:
/// - `direct`: native in-place seek works (confirmed on-device), so the
///   player itself seeks after attaching — [PreparedPlayback.playerStartSeconds]
///   carries the offset, [PreparedPlayback.streamOriginSeconds] stays 0.
/// - `remux`: video is a straight copy piped live; the native player
///   rejects `player_set_play_position` outright (confirmed on-device:
///   `PlatformException(SeekTo, Player seek to failed)` on every attempt,
///   scrub or resume). The server's stream handler instead reads a `?seek=`
///   query param and respawns ffmpeg with `-ss` before `-i` — every remux
///   seek is really "attach a fresh stream at a new position," so the seek
///   goes into the URL itself (via [appendStreamSeekParam]) and
///   [PreparedPlayback.playerStartSeconds] stays 0 (no further native seek
///   attempted); [PreparedPlayback.streamOriginSeconds] carries the
///   requested offset as the position anchor for on-screen position/duration
///   math, since copy-mode seeking lands on the keyframe at-or-before it,
///   not the exact second.
Future<PreparedPlayback> preparePlayableSession(
  ApiClient client,
  PrairieSession session,
  PlaybackSessionResponse started,
  double seekSeconds, {
  String? sourceResolution,
  String? maxResolution,
  String? targetResolution,
  int? targetBitrateKbps,
  bool copyVideo = false,
  /// When true, force the HLS/transcode path even for a direct-play base —
  /// used when the viewer picks a lower quality rung.
  bool forceTranscode = false,
  CancelToken? cancelToken,
  Dio? probeDio,
}) async {
  final forceHls = forceTranscode || copyVideo || (targetResolution != null && targetResolution.isNotEmpty);
  if (!needsHlsBootstrap(started.playMethod) && !forceHls) {
    final isRemux = started.playMethod.trim().toLowerCase() == 'remux';
    final clampedSeek = seekSeconds < 0 ? 0.0 : seekSeconds;
    var url = resolvePlaybackStreamUrl(session.serverUrl, started, session.accessToken);
    if (isRemux && clampedSeek > 0) {
      url = appendStreamSeekParam(url, clampedSeek);
    }
    return PreparedPlayback(
      session: started,
      streamUrl: url,
      playerStartSeconds: isRemux ? 0 : clampedSeek,
      streamOriginSeconds: isRemux ? clampedSeek : 0,
    );
  }

  final playMethod = forceHls && started.playMethod.trim().toLowerCase() == 'direct'
      ? 'transcode'
      : (copyVideo ? 'remux' : started.playMethod);

  final transcode = await startTranscode(
    client,
    session,
    buildTranscodeStartRequest(
      TranscodeStartInput(
        sessionId: started.sessionId,
        seekSeconds: seekSeconds,
        playMethod: playMethod,
        transcodeAudio: true,
        sourceResolution: sourceResolution,
        maxResolution: maxResolution,
        targetResolution: targetResolution,
        targetBitrateKbps: targetBitrateKbps,
        copyVideo: copyVideo,
      ),
    ),
  );

  final streamOriginSeconds = (transcode.streamOriginSeconds ?? 0) < 0 ? 0.0 : (transcode.streamOriginSeconds ?? 0);
  final playerStartSeconds = () {
    final advertised = transcode.playerStartSeconds;
    if (advertised != null) return advertised < 0 ? 0.0 : advertised;
    return streamOriginSeconds > 0 ? 0.0 : (seekSeconds < 0 ? 0.0 : seekSeconds);
  }();
  final mediaPosition = streamOriginSeconds + playerStartSeconds;
  final sessionId = transcode.sessionId.isNotEmpty ? transcode.sessionId : started.sessionId;

  final next = PlaybackSessionResponse(
    sessionId: sessionId,
    mediaFileId: started.mediaFileId,
    playMethod: 'transcode',
    position: mediaPosition > 0 ? mediaPosition : started.position,
    isPaused: started.isPaused,
    streamUrl: transcode.manifestUrl,
    audioTrackIndex: started.audioTrackIndex,
    durationSeconds: transcode.durationSeconds ?? started.durationSeconds,
    playbackInfo: PlaybackInfo(
      streamType: 'hls',
      canSeekAnywhere: transcode.canSeekAnywhere ?? started.playbackInfo?.canSeekAnywhere,
      transcodeAudio: false,
      videoCodec: started.playbackInfo?.videoCodec,
      audioCodec: started.playbackInfo?.audioCodec,
    ),
  );

  final streamUrl = buildStreamUrl(session.serverUrl, transcode.manifestUrl, session.accessToken);

  try {
    // Prefer an explicit probe Dio; otherwise reuse ApiClient's Dio so HLS
    // readiness polls advertise Prairie-SmartTV/… instead of Dart/x.y.
    await waitForHlsManifest(
      streamUrl,
      dio: probeDio ?? client.dio,
      timeout: transcodeStartupTimeout,
      requireSegment: true,
      throwOnTimeout: true,
      keepAliveEvery: const Duration(seconds: 10),
      cancelToken: cancelToken,
      onKeepAlive: () => reportPlaybackProgress(client, session, sessionId, mediaPosition, true),
    );
  } catch (err) {
    if (sessionId != started.sessionId) {
      // ignore: unawaited_futures
      stopPlaybackSession(client, session, sessionId).catchError((_) {});
    }
    rethrow;
  }

  return PreparedPlayback(
    session: next,
    streamUrl: streamUrl,
    playerStartSeconds: playerStartSeconds,
    streamOriginSeconds: streamOriginSeconds,
  );
}
