import '../models/auth.dart';
import 'api_client.dart';
import 'api_error.dart';
import 'playback_types.dart';

/// Mirrors `playback_info` from src/player/types.ts.
class PlaybackInfo {
  const PlaybackInfo({
    this.streamType,
    this.canSeekAnywhere,
    this.transcodeAudio,
    this.videoCodec,
    this.audioCodec,
  });

  final String? streamType;
  final bool? canSeekAnywhere;
  final bool? transcodeAudio;
  final String? videoCodec;
  final String? audioCodec;

  factory PlaybackInfo.fromJson(Map<String, dynamic> json) => PlaybackInfo(
    streamType: json['stream_type'] as String?,
    canSeekAnywhere: json['can_seek_anywhere'] as bool?,
    transcodeAudio: json['transcode_audio'] as bool?,
    videoCodec: json['video_codec'] as String?,
    audioCodec: json['audio_codec'] as String?,
  );
}

/// Mirrors `PlaybackSessionResponse` from src/player/types.ts.
class PlaybackSessionResponse {
  const PlaybackSessionResponse({
    required this.sessionId,
    required this.mediaFileId,
    required this.playMethod,
    required this.position,
    required this.isPaused,
    required this.streamUrl,
    required this.audioTrackIndex,
    this.durationSeconds,
    this.playbackInfo,
  });

  final String sessionId;
  final int mediaFileId;
  final String playMethod;
  final double position;
  final bool isPaused;
  final String streamUrl;
  final int audioTrackIndex;
  final double? durationSeconds;
  final PlaybackInfo? playbackInfo;

  factory PlaybackSessionResponse.fromJson(Map<String, dynamic> json) => PlaybackSessionResponse(
    sessionId: json['session_id'] as String,
    mediaFileId: json['media_file_id'] as int,
    playMethod: json['play_method'] as String,
    position: (json['position'] as num).toDouble(),
    isPaused: json['is_paused'] as bool? ?? false,
    streamUrl: json['stream_url'] as String,
    audioTrackIndex: json['audio_track_index'] as int? ?? 0,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    playbackInfo: json['playback_info'] is Map<String, dynamic>
        ? PlaybackInfo.fromJson(json['playback_info'] as Map<String, dynamic>)
        : null,
  );
}

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Mirrors `startPlayback` from src/api/startPlayback.ts.
Future<PlaybackSessionResponse> startPlayback(ApiClient client, PrairieSession session, BuildPlaybackStartInput input) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/playback/start',
    method: 'POST',
    body: buildPlaybackStartRequest(input),
  );
  return PlaybackSessionResponse.fromJson(json);
}

/// Mirrors `resolvePlaybackStreamUrl`.
String resolvePlaybackStreamUrl(String serverUrl, PlaybackSessionResponse session, String accessToken) =>
    buildStreamUrl(serverUrl, session.streamUrl, accessToken);

/// Optional recommendation from `POST .../progress?advice=1`.
///
/// Absent in the steady state by design — acting on one costs a rebuffer.
class PlaybackQualityAdvice {
  const PlaybackQualityAdvice({
    required this.rungId,
    required this.resolution,
    required this.bitrateKbps,
    required this.direction,
    this.reason = '',
    this.observedKbps = 0,
  });

  final String rungId;
  final String resolution;
  final int bitrateKbps;
  final String direction;
  final String reason;
  final int observedKbps;

  factory PlaybackQualityAdvice.fromJson(Map<String, dynamic> json) => PlaybackQualityAdvice(
    rungId: json['rung_id'] as String? ?? '',
    resolution: json['resolution'] as String? ?? '',
    bitrateKbps: (json['bitrate_kbps'] as num?)?.toInt() ?? 0,
    direction: json['direction'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    observedKbps: (json['observed_kbps'] as num?)?.toInt() ?? 0,
  );
}

/// Mirrors `reportPlaybackProgress` from src/api/playbackSession.ts.
///
/// [throughputKbps] and [isBuffering] are optional client-only signals for the
/// quality advice engine. Pass [requestAdvice] to opt into `?advice=1`; without
/// it the server keeps answering 204 with no body.
Future<PlaybackQualityAdvice?> reportPlaybackProgress(
  ApiClient client,
  PrairieSession session,
  String playbackSessionId,
  double position,
  bool isPaused, {
  int? throughputKbps,
  bool? isBuffering,
  bool requestAdvice = false,
}) async {
  final body = <String, dynamic>{
    'position': position,
    'is_paused': isPaused,
    if (throughputKbps != null && throughputKbps > 0) 'throughput_kbps': throughputKbps,
    'is_buffering': ?isBuffering,
  };
  final path = requestAdvice
      ? '/api/v1/playback/${Uri.encodeComponent(playbackSessionId)}/progress?advice=1'
      : '/api/v1/playback/${Uri.encodeComponent(playbackSessionId)}/progress';
  final json = await client.request<dynamic>(
    _sessionOptions(session),
    path,
    method: 'POST',
    body: body,
  );
  if (!requestAdvice || json is! Map) return null;
  final advice = json['advice'];
  if (advice is! Map) return null;
  final parsed = PlaybackQualityAdvice.fromJson(Map<String, dynamic>.from(advice));
  return parsed.rungId.isEmpty ? null : parsed;
}

/// True when DELETE/progress hit a session the server already reaped
/// (ffmpeg failure, idle timeout, prior stop, superseded transcode id).
bool isPlaybackSessionGone(Object error) {
  if (error is! ApiError) return false;
  if (error.status != 404) return false;
  final code = (error.code ?? '').toLowerCase();
  return code.isEmpty ||
      code == 'playback_session_not_found' ||
      code == 'not_found' ||
      code == 'session_not_found';
}

/// Mirrors `stopPlaybackSession`.
///
/// Idempotent: a 404 `playback_session_not_found` is treated as success — the
/// encode job / session is already gone (common after ffmpeg errors).
Future<void> stopPlaybackSession(ApiClient client, PrairieSession session, String playbackSessionId) async {
  final trimmed = playbackSessionId.trim();
  if (trimmed.isEmpty) return;
  try {
    await client.request<dynamic>(
      _sessionOptions(session),
      '/api/v1/playback/${Uri.encodeComponent(trimmed)}',
      method: 'DELETE',
    );
  } on ApiError catch (err) {
    if (isPlaybackSessionGone(err)) return;
    rethrow;
  }
}

/// Mirrors `AudioSwitchResponse` from src/player/types.ts.
class AudioSwitchResponse {
  const AudioSwitchResponse({
    required this.audioTrackIndex,
    required this.playMethod,
    required this.streamUrl,
    this.switchMode,
    this.playerStartSeconds,
    this.streamOriginSeconds,
    this.canSeekAnywhere,
    this.playbackInfo,
  });

  final int audioTrackIndex;
  final String playMethod;
  final String streamUrl;
  final String? switchMode;
  final double? playerStartSeconds;
  final double? streamOriginSeconds;
  final bool? canSeekAnywhere;
  final PlaybackInfo? playbackInfo;

  factory AudioSwitchResponse.fromJson(Map<String, dynamic> json) => AudioSwitchResponse(
    audioTrackIndex: json['audio_track_index'] as int? ?? 0,
    playMethod: json['play_method'] as String? ?? '',
    streamUrl: json['stream_url'] as String? ?? '',
    switchMode: json['switch_mode'] as String?,
    playerStartSeconds: (json['player_start_seconds'] as num?)?.toDouble(),
    streamOriginSeconds: (json['stream_origin_seconds'] as num?)?.toDouble(),
    canSeekAnywhere: json['can_seek_anywhere'] as bool?,
    playbackInfo: json['playback_info'] is Map<String, dynamic>
        ? PlaybackInfo.fromJson(json['playback_info'] as Map<String, dynamic>)
        : null,
  );
}

/// Mirrors `switchPlaybackAudio` — PATCH `/playback/{id}/audio`.
Future<AudioSwitchResponse> switchPlaybackAudio(
  ApiClient client,
  PrairieSession session,
  String playbackSessionId,
  int audioTrackIndex,
  double position,
) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/playback/${Uri.encodeComponent(playbackSessionId)}/audio',
    method: 'PATCH',
    body: {
      'audio_track_index': audioTrackIndex,
      'position': position < 0 ? 0 : position,
    },
  );
  return AudioSwitchResponse.fromJson(json);
}
