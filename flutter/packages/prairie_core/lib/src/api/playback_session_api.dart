import 'dart:math' as math;

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
    this.playbackAttemptId,
    this.planId,
    this.planAttemptKey,
    this.attemptedPlanKeys = const [],
    this.clientFeatures = const [],
    this.clientCapabilities = const {},
    this.clientPlaybackContext = const {},
    this.isProtocolV3 = false,
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
  final String? playbackAttemptId;
  final String? planId;
  final String? planAttemptKey;
  final List<String> attemptedPlanKeys;
  final List<String> clientFeatures;
  final Map<String, dynamic> clientCapabilities;
  final Map<String, dynamic> clientPlaybackContext;
  final bool isProtocolV3;

  factory PlaybackSessionResponse.fromJson(Map<String, dynamic> json) {
    final plan = json['playback_plan'];
    if (plan is Map<String, dynamic>) {
      return PlaybackSessionResponse.fromV3Decision(json);
    }
    if (json['outcome'] is String) {
      throw FormatException('Prairie playback was not playable: ${json['outcome']}');
    }
    return PlaybackSessionResponse(
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

  factory PlaybackSessionResponse.fromV3Decision(Map<String, dynamic> json) {
    final plan = Map<String, dynamic>.from(json['playback_plan'] as Map);
    final delivery = (plan['delivery'] as String? ?? '').toLowerCase();
    final stream = Map<String, dynamic>.from(plan['stream'] as Map? ?? const {});
    final timeline = Map<String, dynamic>.from(plan['timeline'] as Map? ?? const {});
    final source = Map<String, dynamic>.from(plan['source'] as Map? ?? const {});
    final selected = Map<String, dynamic>.from(plan['selected_tracks'] as Map? ?? const {});
    final audio = selected['audio'] is Map ? Map<String, dynamic>.from(selected['audio'] as Map) : null;
    final recipe = Map<String, dynamic>.from(plan['effective_recipe'] as Map? ?? const {});

    final playMethod = switch (delivery) {
      'original_http' => 'direct',
      'server_remux_progressive' => 'remux',
      _ => 'transcode',
    };

    final streamProtocol = stream['protocol'] as String?;
    final streamUrl = stream['url'] as String? ?? '';
    final playerStart = (timeline['player_start_seconds'] as num?)?.toDouble() ?? 0;
    final streamOrigin = (timeline['stream_origin_seconds'] as num?)?.toDouble() ?? 0;

    return PlaybackSessionResponse(
      sessionId: json['session_id'] as String? ?? plan['session_id'] as String? ?? '',
      mediaFileId: _intFromDynamic(plan['effective_media_file_id'] ?? plan['requested_media_file_id']),
      playMethod: playMethod,
      position: playerStart + streamOrigin,
      isPaused: false,
      streamUrl: streamUrl,
      audioTrackIndex: (audio?['index'] as num?)?.toInt() ?? 0,
      durationSeconds: (source['duration_seconds'] as num?)?.toDouble(),
      playbackInfo: PlaybackInfo(
        streamType: streamProtocol,
        canSeekAnywhere: timeline['can_seek_anywhere'] as bool?,
        transcodeAudio: playMethod == 'transcode',
        videoCodec: recipe['video_codec'] as String?,
        audioCodec: recipe['audio_codec'] as String?,
      ),
      playbackAttemptId: json['playback_attempt_id'] as String?,
      planId: plan['plan_id'] as String?,
      planAttemptKey: plan['plan_attempt_key'] as String?,
      attemptedPlanKeys: const [],
      isProtocolV3: true,
    );
  }

  static int _intFromDynamic(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
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
  final body = buildPlaybackStartRequest(input);
  Map<String, dynamic> json;
  try {
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), '/api/v2/playback/start', method: 'POST', body: body,
    );
  } on ApiError catch (err) {
    if (err.status != 404 && err.status != 405) rethrow;
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), '/api/v1/playback/start', method: 'POST', body: body,
    );
  }
  final parsed = PlaybackSessionResponse.fromJson(json);
  return PlaybackSessionResponse(
    sessionId: parsed.sessionId, mediaFileId: parsed.mediaFileId, playMethod: parsed.playMethod,
    position: parsed.position, isPaused: parsed.isPaused, streamUrl: parsed.streamUrl,
    audioTrackIndex: parsed.audioTrackIndex, durationSeconds: parsed.durationSeconds, playbackInfo: parsed.playbackInfo,
    playbackAttemptId: parsed.playbackAttemptId ?? body['playback_attempt_id'] as String?,
    planId: parsed.planId, planAttemptKey: parsed.planAttemptKey,
    attemptedPlanKeys: parsed.planAttemptKey == null ? const [] : [parsed.planAttemptKey!],
    clientFeatures: List<String>.from(body['client_features'] as List? ?? const []),
    clientCapabilities: Map<String, dynamic>.from(body['client_capabilities'] as Map? ?? const {}),
    clientPlaybackContext: Map<String, dynamic>.from(body['client_playback_context'] as Map? ?? const {}),
    isProtocolV3: parsed.isProtocolV3,
  );
}

Future<PlaybackSessionResponse> replanPlaybackQuality(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String qualityPreference, required double positionSeconds, int attemptCount = 1,
}) async {
  final attemptId = current.playbackAttemptId, planId = current.planId, planKey = current.planAttemptKey;
  if (attemptId == null || planId == null || planKey == null) throw StateError('Protocol-v3 playback metadata is unavailable for quality replan');
  final body = <String, dynamic>{
    'protocol_version': 3, 'client_features': current.clientFeatures, 'operation': 'quality_change',
    'playback_attempt_id': attemptId, 'replan_request_id': _newPlaybackRequestId(),
    'failed_plan_id': planId, 'plan_attempt_id': _newPlaybackRequestId(), 'plan_attempt_key': planKey,
    'attempted_plan_keys': current.attemptedPlanKeys, 'attempt_count': attemptCount.clamp(1, 8),
    'quality_preference': qualityPreference, 'position_seconds': positionSeconds < 0 ? 0.0 : positionSeconds,
    'metered': false, 'selected_tracks': const <String, dynamic>{},
    'client_capabilities': current.clientCapabilities, 'client_playback_context': current.clientPlaybackContext,
  };
  Map<String, dynamic> json;
  final v2Path = '/api/v2/playback/' + Uri.encodeComponent(current.sessionId) + '/replan';
  try {
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), v2Path, method: 'POST', body: body,
    );
  } on ApiError catch (err) {
    if (err.status != 404 && err.status != 405) rethrow;
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), '/api/v1/playback/' + Uri.encodeComponent(current.sessionId) + '/replan',
      method: 'POST', body: body,
    );
  }
  final parsed = PlaybackSessionResponse.fromJson(json);
  final nextKey = parsed.planAttemptKey;
  return PlaybackSessionResponse(
    sessionId: parsed.sessionId.isNotEmpty ? parsed.sessionId : current.sessionId, mediaFileId: parsed.mediaFileId,
    playMethod: parsed.playMethod, position: parsed.position, isPaused: current.isPaused, streamUrl: parsed.streamUrl,
    audioTrackIndex: parsed.audioTrackIndex, durationSeconds: parsed.durationSeconds ?? current.durationSeconds,
    playbackInfo: parsed.playbackInfo, playbackAttemptId: current.playbackAttemptId, planId: parsed.planId, planAttemptKey: nextKey,
    attemptedPlanKeys: [...current.attemptedPlanKeys, if (nextKey != null && !current.attemptedPlanKeys.contains(nextKey)) nextKey],
    clientFeatures: current.clientFeatures, clientCapabilities: current.clientCapabilities, clientPlaybackContext: current.clientPlaybackContext,
    isProtocolV3: true,
  );
}

String _newPlaybackRequestId() {
  final random = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Mirrors `resolvePlaybackStreamUrl`.
String resolvePlaybackStreamUrl(String serverUrl, PlaybackSessionResponse session, String accessToken) {
  // Protocol-v3 plans normally return an already-authorized stream URL. Do
  // not append the legacy session token a second time; v3 signatures cover the
  // URL's complete query string.
  final uri = Uri.tryParse(session.streamUrl);
  if (uri != null && uri.queryParameters.containsKey('token')) {
    return session.streamUrl;
  }
  return buildStreamUrl(serverUrl, session.streamUrl, accessToken);
}

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
