import 'dart:async';
import 'dart:io' show HttpException, SocketException;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/auth.dart';
import 'api_client.dart';
import 'api_error.dart';
import 'playback_types.dart';

/// Server feature that makes `seek_reanchor` / `seek_failure_recovery`
/// replans available (`server_features` on a decision). Mirrors
/// web/android/apple, which all gate on it.
const featureSeekReanchorV3 = 'seek_reanchor_v1';

/// `attempt_count` ceiling from the v2 replan schema (`maximum: 8`).
const maxPlaybackAttemptCountV3 = 8;

/// `attempted_plan_keys` ceiling from the v2 replan schema (`maxItems: 16`).
const maxAttemptedPlanKeysV3 = 16;

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

/// A protocol-v3 plan's `timeline` (TimelineV3). Every position here is in
/// source (media) seconds except [playerStartSeconds], which is in the
/// player's own clock: media time = player time + [timelineOffsetSeconds].
///
/// The server anchors the stream itself (the seek is baked into
/// `stream.url`); the client only reads these numbers, it never derives them
/// from the position it asked for.
class PlaybackTimeline {
  const PlaybackTimeline({
    this.sourceStartSeconds = 0,
    this.streamOriginSeconds = 0,
    this.playerStartSeconds = 0,
    this.timelineOffsetSeconds = 0,
    this.seekWindowStartSeconds,
    this.seekWindowEndSeconds,
    this.canSeekAnywhere = false,
    this.seekRestoration,
  });

  final double sourceStartSeconds;
  final double streamOriginSeconds;
  final double playerStartSeconds;
  final double timelineOffsetSeconds;
  final double? seekWindowStartSeconds;

  /// Null with a window start means an open (still-growing) window: only
  /// what the transport has produced so far is locally seekable.
  final double? seekWindowEndSeconds;
  final bool canSeekAnywhere;
  final String? seekRestoration;

  static double _nonNegative(Object? v) {
    final d = (v as num?)?.toDouble() ?? 0;
    return d.isFinite && d > 0 ? d : 0;
  }

  factory PlaybackTimeline.fromJson(Map<String, dynamic> json) {
    final origin = _nonNegative(json['stream_origin_seconds']);
    return PlaybackTimeline(
      sourceStartSeconds: _nonNegative(json['source_start_seconds']),
      streamOriginSeconds: origin,
      playerStartSeconds: _nonNegative(json['player_start_seconds']),
      // Older plans omitted the offset; it has always equalled the origin.
      timelineOffsetSeconds: json.containsKey('timeline_offset_seconds')
          ? _nonNegative(json['timeline_offset_seconds'])
          : origin,
      seekWindowStartSeconds: (json['seek_window_start_seconds'] as num?)?.toDouble(),
      seekWindowEndSeconds: (json['seek_window_end_seconds'] as num?)?.toDouble(),
      canSeekAnywhere: json['can_seek_anywhere'] as bool? ?? false,
      seekRestoration: json['seek_restoration'] as String?,
    );
  }

  /// Whether a seek to [targetSeconds] (media time) can be served by the
  /// current transport, or needs a `seek_reanchor` replan. Mirrors
  /// VideoPlayer.tsx's `canSeekAnywhere || isNativePositionInRanges(...)`:
  /// TV players expose no seekable ranges, so an open window is bounded by
  /// [producedEndSeconds] (what the transport has produced so far, in media
  /// time), which callers derive from the current position / native duration.
  bool canSeekLocally(double targetSeconds, {double? producedEndSeconds}) {
    if (canSeekAnywhere) return true;
    final start = seekWindowStartSeconds;
    final end = seekWindowEndSeconds;
    // No window published: the transport makes no claim, so try natively.
    if (start == null && end == null) return true;
    if (start != null && targetSeconds < start) return false;
    if (end != null) return targetSeconds <= end;
    return producedEndSeconds != null && targetSeconds <= producedEndSeconds;
  }
}

/// A refused protocol-v3 decision (`outcome` other than `playable`), with the
/// server's `terminal` block when one was sent.
class PlaybackTerminalError extends FormatException {
  PlaybackTerminalError(this.outcome, {this.reason, String? message, this.retryable = false})
    : super(message == null || message.isEmpty ? 'Prairie playback was not playable: $outcome' : message);

  final String outcome;
  final String? reason;
  final bool retryable;
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
    this.planAttemptId,
    this.attemptedPlanKeys = const [],
    this.attemptCount = 1,
    this.clientFeatures = const [],
    this.clientCapabilities = const {},
    this.clientPlaybackContext = const {},
    this.isProtocolV3 = false,
    this.qualityPreference = 'auto',
    this.planSummary,
    this.timeline,
    this.streamHeaders = const {},
    this.streamHeaderRefresh,
    this.serverFeatures = const [],
    this.selectedTracks = const {},
  });

  final String sessionId;
  final int mediaFileId;
  final String playMethod;
  final double position;
  final bool isPaused;

  /// For protocol-v3 plans this is `stream.url` verbatim: server-anchored
  /// (seek baked in) and signed over its whole query. Never rewrite it.
  final String streamUrl;
  final int audioTrackIndex;
  final double? durationSeconds;
  final PlaybackInfo? playbackInfo;
  final String? playbackAttemptId;
  final String? planId;
  final String? planAttemptKey;

  /// Client-minted identity of this adopted plan (`plan_attempt_id`), reused
  /// by every replan and route event off it — mirrors web's planAttemptIdRef.
  final String? planAttemptId;

  /// Plan keys a failure recovery has already excluded. Intent replans
  /// (quality/track/seek) reset this, like web.
  final List<String> attemptedPlanKeys;

  /// The `attempt_count` the next failure recovery sends (1..8).
  final int attemptCount;
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

  /// The plan's `timeline`; null for legacy sessions.
  final PlaybackTimeline? timeline;

  /// `stream.headers`. Carried for completeness: TV players take a URL only,
  /// so media auth rides the URL's `st=` grant and these cannot be applied.
  final Map<String, String> streamHeaders;

  /// `stream.header_refresh` (e.g. `none`).
  final String? streamHeaderRefresh;

  /// `server_features` from the decision that produced this plan.
  final List<String> serverFeatures;

  /// The plan's `selected_tracks`, reduced to the TrackIdentityV3 shape
  /// (`id` + `index`) the replan schema accepts.
  final Map<String, dynamic> selectedTracks;

  bool get supportsSeekReanchor => isProtocolV3 && serverFeatures.contains(featureSeekReanchorV3);

  PlaybackSessionResponse copyWith({
    String? sessionId,
    bool? isPaused,
    double? durationSeconds,
    String? playbackAttemptId,
    List<String>? attemptedPlanKeys,
    int? attemptCount,
    List<String>? clientFeatures,
    Map<String, dynamic>? clientCapabilities,
    Map<String, dynamic>? clientPlaybackContext,
    String? qualityPreference,
    List<String>? serverFeatures,
  }) => PlaybackSessionResponse(
    sessionId: sessionId ?? this.sessionId,
    mediaFileId: mediaFileId,
    playMethod: playMethod,
    position: position,
    isPaused: isPaused ?? this.isPaused,
    streamUrl: streamUrl,
    audioTrackIndex: audioTrackIndex,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    playbackInfo: playbackInfo,
    playbackAttemptId: playbackAttemptId ?? this.playbackAttemptId,
    planId: planId,
    planAttemptKey: planAttemptKey,
    planAttemptId: planAttemptId,
    attemptedPlanKeys: attemptedPlanKeys ?? this.attemptedPlanKeys,
    attemptCount: attemptCount ?? this.attemptCount,
    clientFeatures: clientFeatures ?? this.clientFeatures,
    clientCapabilities: clientCapabilities ?? this.clientCapabilities,
    clientPlaybackContext: clientPlaybackContext ?? this.clientPlaybackContext,
    isProtocolV3: isProtocolV3,
    qualityPreference: qualityPreference ?? this.qualityPreference,
    planSummary: planSummary,
    timeline: timeline,
    streamHeaders: streamHeaders,
    streamHeaderRefresh: streamHeaderRefresh,
    serverFeatures: serverFeatures ?? this.serverFeatures,
    selectedTracks: selectedTracks,
  );

  factory PlaybackSessionResponse.fromJson(Map<String, dynamic> json) {
    final plan = json['playback_plan'];
    if (plan is Map<String, dynamic>) {
      return PlaybackSessionResponse.fromV3Decision(json);
    }
    final outcome = json['outcome'];
    if (outcome is String) {
      final terminal = json['terminal'] is Map ? Map<String, dynamic>.from(json['terminal'] as Map) : const <String, dynamic>{};
      throw PlaybackTerminalError(
        outcome,
        reason: terminal['reason'] as String?,
        message: terminal['message'] as String?,
        retryable: terminal['retryable'] as bool? ?? false,
      );
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
    final timelineJson = Map<String, dynamic>.from(plan['timeline'] as Map? ?? const {});
    final source = Map<String, dynamic>.from(plan['source'] as Map? ?? const {});
    final selected = Map<String, dynamic>.from(plan['selected_tracks'] as Map? ?? const {});
    final audio = selected['audio'] is Map ? Map<String, dynamic>.from(selected['audio'] as Map) : null;
    final recipe = Map<String, dynamic>.from(plan['effective_recipe'] as Map? ?? const {});
    final timeline = PlaybackTimeline.fromJson(timelineJson);

    final playMethod = switch (delivery) {
      'original_http' => 'direct',
      'server_remux_progressive' => 'remux',
      _ => 'transcode',
    };

    final streamProtocol = stream['protocol'] as String?;
    final streamUrl = stream['url'] as String? ?? '';
    final rawHeaders = stream['headers'];
    final headers = <String, String>{
      if (rawHeaders is Map)
        for (final e in rawHeaders.entries)
          if (e.value is String) e.key.toString(): e.value as String,
    };
    final rawFeatures = json['server_features'];

    return PlaybackSessionResponse(
      sessionId: json['session_id'] as String? ?? plan['session_id'] as String? ?? '',
      mediaFileId: _intFromDynamic(plan['effective_media_file_id'] ?? plan['requested_media_file_id']),
      playMethod: playMethod,
      // Media position the player lands on: player clock + offset.
      position: timeline.playerStartSeconds + timeline.timelineOffsetSeconds,
      isPaused: false,
      streamUrl: streamUrl,
      audioTrackIndex: (audio?['index'] as num?)?.toInt() ?? 0,
      durationSeconds: (source['duration_seconds'] as num?)?.toDouble(),
      playbackInfo: PlaybackInfo(
        streamType: streamProtocol,
        canSeekAnywhere: timeline.canSeekAnywhere,
        transcodeAudio: playMethod == 'transcode',
        videoCodec: recipe['video_codec'] as String?,
        audioCodec: recipe['audio_codec'] as String?,
      ),
      playbackAttemptId: json['playback_attempt_id'] as String?,
      planSummary: _planSummary(plan, stream, recipe),
      planId: plan['plan_id'] as String?,
      planAttemptKey: plan['plan_attempt_key'] as String?,
      planAttemptId: _newPlaybackRequestId(),
      isProtocolV3: true,
      timeline: timeline,
      streamHeaders: headers,
      streamHeaderRefresh: stream['header_refresh'] as String?,
      serverFeatures: [
        if (rawFeatures is List)
          for (final f in rawFeatures)
            if (f is String) f,
      ],
      selectedTracks: trackIdentitiesV3(selected),
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

/// Reduces a plan's `selected_tracks` to SelectedTracksV3: only `audio` /
/// `subtitle`, each only `id` (required) + `index`. The replan schema is
/// `additionalProperties: false`, and plans carry richer track objects.
Map<String, dynamic> trackIdentitiesV3(Map<String, dynamic> selected) {
  Map<String, dynamic>? identity(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final index = raw['index'];
    return {
      'id': id is String ? id : '',
      if (index is num) 'index': index.toInt(),
    };
  }

  final audio = identity(selected['audio']);
  final subtitle = identity(selected['subtitle']);
  return {'audio': ?audio, 'subtitle': ?subtitle};
}

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Whether a failed playback request is worth retrying with the identical
/// body: a 5xx, no HTTP status at all, or a transport failure. A 4xx is a
/// refusal and final. Mirrors `isTransient` in web start-v2.ts /
/// session-mutations.ts.
bool isTransientPlaybackError(Object error) {
  if (error is ApiError) return error.status >= 500 || error.status == 0;
  if (error is DioException) return error.type != DioExceptionType.cancel;
  return error is SocketException || error is HttpException || error is TimeoutException;
}

/// Pause between playback retries. Tests replace it to run without waiting.
@visibleForTesting
Future<void> Function(Duration) playbackRetryPause = (d) => Future<void>.delayed(d);

/// Runs [op] until it succeeds, fails non-transiently, or [budget] elapses,
/// backing off `min(maxPause, basePause * 2^attempt)` between attempts.
Future<T> _retryTransient<T>(
  Future<T> Function() op, {
  required Duration budget,
  Duration basePause = const Duration(milliseconds: 500),
  Duration maxPause = const Duration(seconds: 5),
  int? maxAttempts,
  CancelToken? cancelToken,
}) async {
  final clock = Stopwatch()..start();
  for (var attempt = 0; ; attempt++) {
    try {
      return await op();
    } catch (err) {
      if (cancelToken?.isCancelled ?? false) rethrow;
      if (!isTransientPlaybackError(err)) rethrow;
      if (maxAttempts != null && attempt + 1 >= maxAttempts) rethrow;
      final remaining = budget - clock.elapsed;
      if (remaining <= Duration.zero) rethrow;
      var wait = basePause * (1 << math.min(attempt, 10));
      if (wait > maxPause) wait = maxPause;
      if (wait > remaining) wait = remaining;
      await playbackRetryPause(wait);
      if (clock.elapsed >= budget || (cancelToken?.isCancelled ?? false)) rethrow;
    }
  }
}

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

/// Start retry budget, like web's START_BUDGET_MS. Start is idempotent on
/// `playback_attempt_id` + body digest, so a retry after a lost reply returns
/// the stored decision rather than a second session.
const _startRetryBudget = Duration(seconds: 60);

/// Stop retry budget. Shorter than web's 30s because exit awaits the stop
/// (single hardware decoder / encode slot) and a TV has no keepalive fetch.
const _stopRetryBudget = Duration(seconds: 10);

typedef _ProgressSample = ({double position, bool isPaused});

/// Sequencing state for a session started on /api/v2 (mirrors
/// web/src/player/session-mutations.ts). The server orders progress with a
/// compare-and-set on `sequence`, so samples go out one at a time in
/// sequence order, and a stop keeps one exact body (one `stop_id`) across
/// retries. Sessions absent from this map were started on the v1 bridge and
/// keep the v1 lifecycle routes.
class _V2Mutations {
  _V2Mutations(this.installationId);
  final String installationId;
  int sequence = 0;
  Future<void> tail = Future<void>.value();
  _ProgressSample? latestSample;
  Map<String, dynamic>? stopBody;

  /// Terminal: the server answered the stop (or the session is gone). The
  /// entry is kept so late progress is dropped instead of falling through to
  /// the v1 routes, and a second stop is a no-op.
  bool stopped = false;
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

/// Mirrors `startPlayback` from src/api/startPlayback.ts / `startPlaybackV2`.
///
/// Starts on /api/v2 when the server offers protocol v3 there, else on the
/// frozen /api/v1 bridge. A transient failure (5xx, network) retries the
/// identical body with backoff for up to a minute, like web.
Future<PlaybackSessionResponse> startPlayback(
  ApiClient client,
  PrairieSession session,
  BuildPlaybackStartInput input, {
  CancelToken? cancelToken,
}) async {
  final body = buildPlaybackStartRequest(input);
  var installationId = await _retryTransient(
    () => _playbackInstallationV2(client, session),
    budget: const Duration(seconds: 15),
    cancelToken: cancelToken,
  );
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> payload) => _retryTransient(
    () => client.request<Map<String, dynamic>>(_sessionOptions(session), path, method: 'POST', body: payload),
    budget: _startRetryBudget,
    cancelToken: cancelToken,
  );
  Map<String, dynamic> json;
  if (installationId != null) {
    try {
      json = await post('/api/v2/playback/start', _startBodyV2(body, installationId));
    } on ApiError catch (err) {
      if (err.code != 'installation_changed') rethrow;
      // The server was reinstalled since capabilities were read; retry once
      // with the new installation.
      installationId = await _playbackInstallationV2(client, session, force: true);
      if (installationId == null) rethrow;
      json = await post('/api/v2/playback/start', _startBodyV2(body, installationId));
    }
  } else {
    json = await post('/api/v1/playback/start', body);
  }
  final parsed = PlaybackSessionResponse.fromJson(json);
  final registeredInstallation = installationId;
  if (registeredInstallation != null && parsed.sessionId.isNotEmpty) {
    _v2Sessions.putIfAbsent(parsed.sessionId, () => _V2Mutations(registeredInstallation));
  }
  return parsed.copyWith(
    playbackAttemptId: parsed.playbackAttemptId ?? body['playback_attempt_id'] as String?,
    attemptedPlanKeys: const [],
    attemptCount: 1,
    clientFeatures: List<String>.from(body['client_features'] as List? ?? const []),
    clientCapabilities: Map<String, dynamic>.from(body['client_capabilities'] as Map? ?? const {}),
    clientPlaybackContext: Map<String, dynamic>.from(body['client_playback_context'] as Map? ?? const {}),
    qualityPreference: body['quality_preference'] as String? ?? 'auto',
  );
}

/// Failure recovery ran out of attempts (`attempt_count` would pass 8).
class PlaybackRecoveryExhaustedError implements Exception {
  const PlaybackRecoveryExhaustedError();
  @override
  String toString() => 'Playback failed after repeated recovery attempts.';
}

bool _isRecoveryOperation(String operation) =>
    operation == 'failure_recovery' || operation == 'seek_failure_recovery';

/// Builds a `PlaybackReplanBody` (v2 openapi, additionalProperties: false).
///
/// Mirrors web's `buildReplanRequestV3` + usePlaybackSession's replan: an
/// intent change (quality/track/seek) resets `attempted_plan_keys` and
/// `attempt_count`, since nothing failed; only a recovery accumulates them,
/// folding the failed plan's key in so the server excludes that route.
/// `selected_tracks` defaults to the plan's own, with [selectedTracks]
/// overriding per kind.
@visibleForTesting
Map<String, dynamic> buildReplanBody(
  PlaybackSessionResponse current, {
  required String operation,
  required String qualityPreference,
  required double positionSeconds,
  required String replanRequestId,
  String? installationId,
  Map<String, dynamic> selectedTracks = const {},
  Map<String, dynamic>? failure,
}) {
  final attemptId = current.playbackAttemptId, planId = current.planId, planKey = current.planAttemptKey;
  if (attemptId == null || planId == null || planKey == null) {
    throw StateError('Protocol-v3 playback metadata is unavailable for replan');
  }
  final recovery = _isRecoveryOperation(operation);
  var attemptedKeys = const <String>[];
  if (recovery) {
    attemptedKeys = [...current.attemptedPlanKeys.where((k) => k != planKey), planKey];
    if (attemptedKeys.length > maxAttemptedPlanKeysV3) {
      attemptedKeys = attemptedKeys.sublist(attemptedKeys.length - maxAttemptedPlanKeysV3);
    }
  }
  final attemptCount = recovery ? math.max(1, math.min(current.attemptCount, maxPlaybackAttemptCountV3)) : 1;
  return <String, dynamic>{
    'installation_id': ?installationId,
    'protocol_version': 3,
    'client_features': current.clientFeatures,
    'operation': operation,
    'playback_attempt_id': attemptId,
    'replan_request_id': replanRequestId,
    'failed_plan_id': planId,
    'plan_attempt_id': current.planAttemptId ?? replanRequestId,
    'plan_attempt_key': planKey,
    'attempted_plan_keys': attemptedKeys,
    'attempt_count': attemptCount,
    'quality_preference': qualityPreference,
    'position_seconds': _clampPosition(positionSeconds),
    'metered': false,
    'selected_tracks': {...current.selectedTracks, ...selectedTracks},
    'client_capabilities': current.clientCapabilities,
    'client_playback_context': current.clientPlaybackContext,
    'failure': ?failure,
  };
}

Future<PlaybackSessionResponse> _replanPlayback(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String operation, required String qualityPreference, required double positionSeconds,
  Map<String, dynamic> selectedTracks = const {}, Map<String, dynamic>? failure,
}) async {
  final recovery = _isRecoveryOperation(operation);
  if (recovery && current.attemptCount > maxPlaybackAttemptCountV3) throw const PlaybackRecoveryExhaustedError();
  final v2 = _v2Sessions[current.sessionId];
  final body = buildReplanBody(
    current,
    operation: operation,
    qualityPreference: qualityPreference,
    positionSeconds: positionSeconds,
    replanRequestId: _newPlaybackRequestId(),
    installationId: v2?.installationId,
    selectedTracks: selectedTracks,
    failure: failure,
  );
  final api = v2 != null ? 'v2' : 'v1';
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session), '/api/$api/playback/${Uri.encodeComponent(current.sessionId)}/replan',
    method: 'POST', body: body,
  );
  final parsed = PlaybackSessionResponse.fromJson(json);
  final sessionId = parsed.sessionId.isNotEmpty ? parsed.sessionId : current.sessionId;
  if (v2 != null && sessionId != current.sessionId) _v2Sessions.putIfAbsent(sessionId, () => _V2Mutations(v2.installationId));
  final sentCount = body['attempt_count'] as int;
  return parsed.copyWith(
    sessionId: sessionId,
    isPaused: current.isPaused,
    durationSeconds: parsed.durationSeconds ?? current.durationSeconds,
    playbackAttemptId: current.playbackAttemptId,
    attemptedPlanKeys: List<String>.from(body['attempted_plan_keys'] as List),
    attemptCount: recovery ? math.min(sentCount + 1, maxPlaybackAttemptCountV3 + 1) : 1,
    clientFeatures: current.clientFeatures,
    clientCapabilities: current.clientCapabilities,
    clientPlaybackContext: current.clientPlaybackContext,
    qualityPreference: qualityPreference,
    serverFeatures: parsed.serverFeatures.isNotEmpty ? parsed.serverFeatures : current.serverFeatures,
  );
}

Future<PlaybackSessionResponse> replanPlaybackQuality(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String qualityPreference, required double positionSeconds,
}) => _replanPlayback(client, session, current,
  operation: 'quality_change', qualityPreference: qualityPreference, positionSeconds: positionSeconds,
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

/// Re-anchors the stream at [positionSeconds] on the current tracks
/// (`seek_reanchor`): for seeks the current transport cannot serve. Callers
/// check [PlaybackSessionResponse.supportsSeekReanchor] first.
Future<PlaybackSessionResponse> replanPlaybackSeek(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required double positionSeconds,
}) => _replanPlayback(client, session, current,
  operation: 'seek_reanchor', qualityPreference: current.qualityPreference, positionSeconds: positionSeconds,
);

/// `failure_recovery` replan after the device could not play the plan: the
/// failed route's key joins `attempted_plan_keys` so the server picks
/// another. Throws [PlaybackRecoveryExhaustedError] past 8 attempts.
Future<PlaybackSessionResponse> replanPlaybackFailure(ApiClient client, PrairieSession session, PlaybackSessionResponse current, {
  required String classification, String? message, required double positionSeconds,
}) => _replanPlayback(client, session, current,
  operation: 'failure_recovery', qualityPreference: current.qualityPreference, positionSeconds: positionSeconds,
  failure: playbackFailureV3(classification, message),
);

/// A FailureV3 block: `classification` (required), optional `message`.
Map<String, dynamic> playbackFailureV3(String classification, [String? message]) {
  final trimmed = classification.trim();
  final text = message?.trim() ?? '';
  return {
    'classification': trimmed.isEmpty ? 'player_failure' : (trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed),
    if (text.isNotEmpty) 'message': text.length > 256 ? text.substring(0, 256) : text,
  };
}

/// Maps a native player error / startup failure to a FailureV3
/// classification, using the Android TV client's vocabulary
/// (`decoder_failure`, `transport_stall`, `http_failure`,
/// `source_unavailable`, `player_failure`).
String classifyPlaybackFailure(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('stall') || text.contains('timed out') || text.contains('timeout')) return 'transport_stall';
  if (RegExp(r'\b(401|403)\b|unauthori[sz]ed|forbidden|not authorized').hasMatch(text)) return 'http_failure';
  if (RegExp(r'\b404\b|not found').hasMatch(text)) return 'source_unavailable';
  if (text.contains('decod') || text.contains('codec') || text.contains('format') || text.contains('unsupported')) {
    return 'decoder_failure';
  }
  if (text.contains('network') || text.contains('connection') || text.contains('socket') || text.contains('http')) {
    return 'transport_stall';
  }
  return 'player_failure';
}

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
///
/// Only joins a relative URL to the server and, when it carries no grant of
/// its own, appends the session token (TV players cannot send headers). It
/// never rewrites the URL's existing query: v3 signatures cover all of it.
String resolvePlaybackStreamUrl(String serverUrl, PlaybackSessionResponse session, String accessToken) {
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

double _clampPosition(double position) => position.isFinite && position > 0 ? position : 0.0;

/// Mirrors `reportPlaybackProgress` from src/api/playbackSession.ts and, for
/// v2 sessions, `sendSessionProgress` from session-mutations.ts: samples are
/// serialized (one request in flight), each takes the next `sequence` when it
/// is queued, and a transient failure retries the identical body (up to 3
/// sends, 250 ms apart).
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
    if (v2.stopBody != null) return null;
    final _ProgressSample sample = (position: _clampPosition(position), isPaused: isPaused);
    v2.latestSample = sample;
    final body = <String, dynamic>{
      'installation_id': v2.installationId,
      'sequence': ++v2.sequence,
      'position': sample.position,
      'is_paused': sample.isPaused,
    };
    final pending = v2.tail.catchError((Object _) {}).then(
      (_) => _retryTransient(
        () => client.request<dynamic>(
          _sessionOptions(session),
          '/api/v2/playback/${Uri.encodeComponent(playbackSessionId)}/progress',
          method: 'POST',
          body: body,
        ),
        budget: const Duration(seconds: 15),
        basePause: const Duration(milliseconds: 250),
        maxPause: const Duration(milliseconds: 250),
        maxAttempts: 3,
      ),
    );
    v2.tail = pending.then((_) {});
    await pending;
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

/// Mirrors `stopPlaybackSession` / web's `stopSequencedSession`.
///
/// Idempotent: a 404 `playback_session_not_found` is treated as success — the
/// encode job / session is already gone (common after ffmpeg errors).
///
/// A v2 stop carries the final position sample — [position] when given, else
/// the latest progress sample — with its own `sequence`, waits (bounded) for
/// queued progress, then retries its one exact body on transient failures.
/// For a v1 session a given [position] goes out as a last progress report
/// first, since the v1 stop takes no body.
Future<void> stopPlaybackSession(
  ApiClient client,
  PrairieSession session,
  String playbackSessionId, {
  double? position,
  bool isPaused = true,
}) async {
  final trimmed = playbackSessionId.trim();
  if (trimmed.isEmpty) return;
  final v2 = _v2Sessions[trimmed];
  try {
    if (v2 != null) {
      if (v2.stopped) return;
      var stopBody = v2.stopBody;
      if (stopBody == null) {
        final _ProgressSample? sample =
            position != null ? (position: _clampPosition(position), isPaused: isPaused) : v2.latestSample;
        stopBody = <String, dynamic>{
          'installation_id': v2.installationId,
          // One stop_id per session, kept across retries: the server answers
          // `stopped` the first time and `replayed` after, both terminal.
          'stop_id': _newUuidV4(),
          if (sample != null) ...{
            'position': sample.position,
            'is_paused': sample.isPaused,
            'sequence': ++v2.sequence,
          },
        };
        v2.stopBody = stopBody;
      }
      final body = stopBody;
      await v2.tail.catchError((Object _) {}).timeout(const Duration(seconds: 5), onTimeout: () {});
      await _retryTransient(
        () => client.request<dynamic>(
          _sessionOptions(session),
          '/api/v2/playback/${Uri.encodeComponent(trimmed)}',
          method: 'DELETE',
          body: body,
        ),
        budget: _stopRetryBudget,
        maxPause: const Duration(seconds: 1),
      );
      v2.stopped = true;
      return;
    }
    if (position != null) {
      await reportPlaybackProgress(client, session, trimmed, position, isPaused).then((_) {}, onError: (Object _) {});
    }
    await client.request<dynamic>(
      _sessionOptions(session),
      '/api/v1/playback/${Uri.encodeComponent(trimmed)}',
      method: 'DELETE',
    );
  } on ApiError catch (err) {
    if (isPlaybackSessionGone(err)) {
      v2?.stopped = true;
      return;
    }
    rethrow;
  }
}

/// Route events the v2 schema accepts (`PlaybackRouteEventBody.event`).
const playbackRouteEventsV3 = {
  'plan_selected',
  'plan_invalidated',
  'plan_failed',
  'first_frame',
  'terminal',
  'stopped',
  'runtime_correction_applied',
  'runtime_correction_succeeded',
  'runtime_correction_failed',
  'seek_reanchor_requested',
  'seek_reanchored',
};

/// Builds a `PlaybackRouteEventBody` (additionalProperties: false), or null
/// when [playback] is not a registered v2 session.
@visibleForTesting
Map<String, dynamic>? buildRouteEventBody(
  PlaybackSessionResponse playback,
  String event, {
  String? failureClassification,
  String? fallbackReason,
  Map<String, String> diagnostics = const {},
}) {
  final v2 = _v2Sessions[playback.sessionId];
  final attemptId = playback.playbackAttemptId;
  if (v2 == null || attemptId == null || attemptId.length < 8 || !playbackRouteEventsV3.contains(event)) return null;
  String? capped(String? v, int max) => v == null || v.isEmpty ? null : (v.length > max ? v.substring(0, max) : v);
  final diag = <String, String>{};
  for (final e in diagnostics.entries) {
    if (diag.length >= 32) break;
    if (e.value.isEmpty) continue;
    diag[e.key] = e.value.length > 256 ? e.value.substring(0, 256) : e.value;
  }
  return <String, dynamic>{
    'installation_id': v2.installationId,
    'event_id': _newUuidV4(),
    'protocol_version': 3,
    'playback_attempt_id': attemptId,
    'event': event,
    'diagnostics': diag,
    'session_id': ?capped(playback.sessionId, 128),
    'plan_id': ?capped(playback.planId, 128),
    'plan_attempt_id': ?capped(playback.planAttemptId, 128),
    'plan_attempt_key': ?capped(playback.planAttemptKey, 128),
    'failure_classification': ?capped(failureClassification, 64),
    'fallback_reason': ?capped(fallbackReason, 64),
  };
}

/// Reports a route event for a v2 session (`POST /api/v2/playback/route-events`).
/// Diagnostics never control playback: sent once, never retried, and every
/// failure is swallowed (mirrors web route-events-v2.ts). v1 sessions skip.
Future<void> reportPlaybackRouteEvent(
  ApiClient client,
  PrairieSession session,
  PlaybackSessionResponse playback,
  String event, {
  String? failureClassification,
  String? fallbackReason,
  Map<String, String> diagnostics = const {},
}) async {
  final body = buildRouteEventBody(
    playback,
    event,
    failureClassification: failureClassification,
    fallbackReason: fallbackReason,
    diagnostics: diagnostics,
  );
  if (body == null) return;
  try {
    await client.request<dynamic>(_sessionOptions(session), '/api/v2/playback/route-events', method: 'POST', body: body);
  } catch (_) {
    // Dropped, never retried.
  }
}
