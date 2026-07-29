import '../models/auth.dart';
import 'api_client.dart';
import 'playback_types.dart';

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
  });

  final String sessionId;
  final int mediaFileId;
  final String playMethod;
  final double position;
  final bool isPaused;
  final String streamUrl;
  final int audioTrackIndex;
  final double? durationSeconds;

  factory PlaybackSessionResponse.fromJson(Map<String, dynamic> json) => PlaybackSessionResponse(
    sessionId: json['session_id'] as String,
    mediaFileId: json['media_file_id'] as int,
    playMethod: json['play_method'] as String,
    position: (json['position'] as num).toDouble(),
    isPaused: json['is_paused'] as bool,
    streamUrl: json['stream_url'] as String,
    audioTrackIndex: json['audio_track_index'] as int,
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
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

/// Mirrors `stopPlaybackSession`.
Future<void> stopPlaybackSession(ApiClient client, PrairieSession session, String playbackSessionId) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v1/playback/${Uri.encodeComponent(playbackSessionId)}',
  method: 'DELETE',
);
