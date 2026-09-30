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
    this.qualityPreference = 'auto',
    this.planSummary,
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

  /// Quality preference the current plan was made under. A track change
  /// replans with it so switching audio does not reset the chosen quality.
  final String qualityPreference;

  /// One-line description of the server's protocol-v3 plan (route, reason,
  /// container, codecs) for the stats overlay; null for legacy sessions.
  final String? planSummary;

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
      planSummary: _planSummary(plan, stream, recipe),
      planId: plan['plan_id'] as String?,
      planAttemptKey: plan['plan_attempt_key'] as String?,
      attemptedPlanKeys: const [],
      isProtocolV3: true,
    );
  }

  static String _planSummary(Map<String, dynamic> plan, Map<String, dynamic> stream, Map<String, dynamic> recipe) {
    String? str(Object? v) => v == null || v.toString().isEmpty ? null : v.toString();
    final w = recipe['width'], h = recipe['height'];
    final video = [
      str(recipe['video_codec']),
      if (w != null && h != null) '${w}x$h',
      str(recipe['dynamic_range']),
    ].whereType<String>().join(' ');
    final channels = recipe['audio_channels'];
    final audio = [str(recipe['audio_codec']), if (channels != null) '${channels}ch'].whereType<String>().join(' ');
    return [
      str(plan['delivery']),
      if (str(plan['decision_reason']) != null) '(${plan['decision_reason']})',
      if (str(stream['container']) != null) 'container=${stream['container']}',
      if (video.isNotEmpty) 'video=$video',
      if (audio.isNotEmpty) 'audio=$audio',
    ].whereType<String>().join(' ');
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

/// `GET /api/v2/playback/capabilities`, memoized per server for a minute
/// (mirrors `playbackCapabilitiesV2` in web/src/player/start-v2.ts).
class _PlaybackCapabilitiesV2 {
  const _PlaybackCapabilitiesV2(this.at, this.installationId);
  final DateTime at;

  /// Null when this server or account cannot start playback on /api/v2.
  final String? installationId;
}

const _capabilitiesTtl = Duration(minutes: 1);
final _capabilitiesCache = <String, _PlaybackCapabilitiesV2>{};

/// Sequencing state for a session started on /api/v2 (mirrors
/// web/src/player/session-mutations.ts). The server orders progress with a
/// compare-and-set on `sequence`, and a stop keeps one `stop_id` across
/// retries. Sessions absent from this map were started on the v1 bridge and
/// keep the v1 lifecycle routes.
class _V2Mutations {
  _V2Mutations(this.installationId);
  final String installationId;
  int sequence = 0;
  String? stopId;
}

final _v2Sessions = <String, _V2Mutations>{};

/// Forgets memoized capabilities and registered v2 sessions; tests only.
void resetPlaybackV2StateForTest() {
  _capabilitiesCache.clear();
  _v2Sessions.clear();
}

/// The installation to start on /api/v2 with, or null to use the v1 bridge.
Future<String?> _playbackInstallationV2(ApiClient client, PrairieSession session, {bool force = false}) async {
  final key = session.serverUrl;
  final cached = _capabilitiesCache[key];
  if (!force && cached != null && DateTime.now().difference(cached.at) < _capabilitiesTtl) {
    return cached.installationId;
  }
  String? installationId;
  try {
    final cap = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), '/api/v2/playback/capabilities',
    );
    final versions = cap['protocol_versions'];
    final id = cap['installation_id'];
    if (cap['state'] == 'available' &&
        cap['allowed'] == true &&
        versions is List &&
        versions.contains(3) &&
        id is String &&
        id.isNotEmpty) {
      installationId = id;
    }
  } on ApiError catch (err) {
    // A server without /api/v2 playback keeps the v1 bridge. Anything else
    // (auth, 5xx) is a real failure and must not silently change protocol.
    if (err.status != 404 && err.status != 405) rethrow;
  }
  _capabilitiesCache[key] = _PlaybackCapabilitiesV2(DateTime.now(), installationId);
  return installationId;
}

/// Converts the v1-bridge start body to `PlaybackStartBody`: string ids, the
/// capabilities' installation, and no Prairie v1 extras (v2 rejects unknown
/// fields; the channel ceiling already rides on each delivery's
/// `max_channels`).
Map<String, dynamic> _startBodyV2(Map<String, dynamic> body, String installationId) {
  final next = Map<String, dynamic>.from(body)
    ..remove('max_audio_channels')
    ..['file_id'] = body['file_id'].toString()
    ..['installation_id'] = installationId;
  return next;
}

/// Mirrors `startPlayback` from src/api/startPlayback.ts.
///
/// Starts on /api/v2 when the server offers protocol v3 there, else on the
/// frozen /api/v1 bridge.
Future<PlaybackSessionResponse> startPlayback(ApiClient client, PrairieSession session, BuildPlaybackStartInput input) async {
  final body = buildPlaybackStartRequest(input);
  var installationId = await _playbackInstallationV2(client, session);
  Map<String, dynamic> json;
  if (installationId != null) {
    try {
      json = await client.request<Map<String, dynamic>>(
        _sessionOptions(session), '/api/v2/playback/start', method: 'POST', body: _startBodyV2(body, installationId),
      );
    } on ApiError catch (err) {
      if (err.code != 'installation_changed') rethrow;
      // The server was reinstalled since capabilities were read; retry once
      // with the new installation.
      installationId = await _playbackInstallationV2(client, session, force: true);
      if (installationId == null) rethrow;
      json = await client.request<Map<String, dynamic>>(
        _sessionOptions(session), '/api/v2/playback/start', method: 'POST', body: _startBodyV2(body, installationId),
      );
    }
  } else {
    json = await client.request<Map<String, dynamic>>(
      _sessionOptions(session), '/api/v1/playback/start', method: 'POST', body: body,
    );
  }
  final parsed = PlaybackSessionResponse.fromJson(json);
  if (installationId != null && parsed.sessionId.isNotEmpty) {
    _v2Sessions.putIfAbsent(parsed.sessionId, () => _V2Mutations(installationId!));
  }
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
    qualityPreference: body['quality_preference'] as String? ?? 'auto',
    planSummary: parsed.planSummary,
  );
}

Future<PlaybackSessionResponse> _replanPlayback(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String operation, required String qualityPreference, required double positionSeconds,
  Map<String, dynamic> selectedTracks = const {}, int attemptCount = 1,
}) async {
  final attemptId = current.playbackAttemptId, planId = current.planId, planKey = current.planAttemptKey;
  if (attemptId == null || planId == null || planKey == null) throw StateError('Protocol-v3 playback metadata is unavailable for replan');
  final v2 = _v2Sessions[current.sessionId];
  final body = <String, dynamic>{
    'installation_id': ?v2?.installationId,
    'protocol_version': 3, 'client_features': current.clientFeatures, 'operation': operation,
    'playback_attempt_id': attemptId, 'replan_request_id': _newPlaybackRequestId(),
    'failed_plan_id': planId, 'plan_attempt_id': _newPlaybackRequestId(), 'plan_attempt_key': planKey,
    'attempted_plan_keys': current.attemptedPlanKeys, 'attempt_count': attemptCount.clamp(1, 8),
    'quality_preference': qualityPreference, 'position_seconds': positionSeconds < 0 ? 0.0 : positionSeconds,
    'metered': false, 'selected_tracks': selectedTracks,
    'client_capabilities': current.clientCapabilities, 'client_playback_context': current.clientPlaybackContext,
  };
  final api = v2 != null ? 'v2' : 'v1';
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session), '/api/$api/playback/${Uri.encodeComponent(current.sessionId)}/replan',
    method: 'POST', body: body,
  );
  final parsed = PlaybackSessionResponse.fromJson(json);
  final nextKey = parsed.planAttemptKey;
  final sessionId = parsed.sessionId.isNotEmpty ? parsed.sessionId : current.sessionId;
  if (v2 != null && sessionId != current.sessionId) _v2Sessions.putIfAbsent(sessionId, () => _V2Mutations(v2.installationId));
  return PlaybackSessionResponse(
    sessionId: sessionId, mediaFileId: parsed.mediaFileId,
    playMethod: parsed.playMethod, position: parsed.position, isPaused: current.isPaused, streamUrl: parsed.streamUrl,
    audioTrackIndex: parsed.audioTrackIndex, durationSeconds: parsed.durationSeconds ?? current.durationSeconds,
    playbackInfo: parsed.playbackInfo, playbackAttemptId: current.playbackAttemptId, planId: parsed.planId, planAttemptKey: nextKey,
    attemptedPlanKeys: [...current.attemptedPlanKeys, if (nextKey != null && !current.attemptedPlanKeys.contains(nextKey)) nextKey],
    clientFeatures: current.clientFeatures, clientCapabilities: current.clientCapabilities, clientPlaybackContext: current.clientPlaybackContext,
    isProtocolV3: true,
    qualityPreference: qualityPreference,
    planSummary: parsed.planSummary,
  );
}

Future<PlaybackSessionResponse> replanPlaybackQuality(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String qualityPreference, required double positionSeconds, int attemptCount = 1,
}) => _replanPlayback(client, session, current,
  operation: 'quality_change', qualityPreference: qualityPreference, positionSeconds: positionSeconds, attemptCount: attemptCount,
);

/// Switches audio with a protocol-v3 `track_change` replan (the server no
/// longer has the legacy PATCH /audio route). Sending the index alone lets
/// the server resolve the track identity against the effective file.
Future<PlaybackSessionResponse> replanPlaybackAudio(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required int audioTrackIndex, required double positionSeconds,
}) => _replanPlayback(client, session, current,
  operation: 'track_change', qualityPreference: current.qualityPreference, positionSeconds: positionSeconds,
  selectedTracks: {'audio': {'id': '', 'index': audioTrackIndex}},
);

/// Re-anchors the stream at [positionSeconds] on the current tracks: the v3
/// equivalent of restarting the legacy session for a seek outside the window.
Future<PlaybackSessionResponse> replanPlaybackSeek(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required double positionSeconds,
}) => _replanPlayback(client, session, current,
  operation: 'seek_reanchor', qualityPreference: current.qualityPreference, positionSeconds: positionSeconds,
);

/// Canonical lowercase UUIDv4. v2 stop rejects anything else as `stop_id`
/// ("Expected a canonical UUID.") although the published schema only says
/// "opaque identifier".
String _newUuidV4() {
  final random = math.Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
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
  // URL's complete query string. (Relative URLs are still joined to the server.)
  final uri = Uri.tryParse(session.streamUrl);
  // `st` is the v2 stream grant. Appending the session access token beside it
  // is not harmless: the server validates any `token` it is given, so an
  // expired access token 401s a stream the grant alone would authorize.
  if (uri != null && (uri.queryParameters.containsKey('token') || uri.queryParameters.containsKey('st'))) {
    return buildStreamUrl(serverUrl, session.streamUrl, null);
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
  final v2 = _v2Sessions[playbackSessionId];
  if (v2 != null) {
    // v2 carries no throughput/buffering signal and gives no quality advice.
    if (v2.stopId != null) return null;
    await client.request<dynamic>(
      _sessionOptions(session),
      '/api/v2/playback/${Uri.encodeComponent(playbackSessionId)}/progress',
      method: 'POST',
      body: {
        'installation_id': v2.installationId,
        'sequence': ++v2.sequence,
        'position': position < 0 ? 0.0 : position,
        'is_paused': isPaused,
      },
    );
    return null;
  }
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
  final v2 = _v2Sessions[trimmed];
  try {
    if (v2 != null) {
      // One stop_id per session, kept across retries: the server answers
      // `stopped` the first time and `replayed` after, both terminal.
      v2.stopId ??= _newUuidV4();
      await client.request<dynamic>(
        _sessionOptions(session),
        '/api/v2/playback/${Uri.encodeComponent(trimmed)}',
        method: 'DELETE',
        body: {'installation_id': v2.installationId, 'stop_id': v2.stopId},
      );
      _v2Sessions.remove(trimmed);
      return;
    }
    await client.request<dynamic>(
      _sessionOptions(session),
      '/api/v1/playback/${Uri.encodeComponent(trimmed)}',
      method: 'DELETE',
    );
  } on ApiError catch (err) {
    if (isPlaybackSessionGone(err)) {
      _v2Sessions.remove(trimmed);
      return;
    }
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
