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

/// Mirrors `reportPlaybackProgress` from src/api/playbackSession.ts.
Future<void> reportPlaybackProgress(ApiClient client, PrairieSession session, String playbackSessionId, double position, bool isPaused) =>
    client.request<dynamic>(
      _sessionOptions(session),
      '/api/v1/playback/${Uri.encodeComponent(playbackSessionId)}/progress',
      method: 'POST',
      body: {'position': position, 'is_paused': isPaused},
    );

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
