import '../models/auth.dart';
import '../models/live_tv_channel.dart';
import 'api_client.dart';
import 'api_error.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

LiveTvChannel _channelFromJson(Map<String, dynamic> json) => LiveTvChannel(
  id: json['id'] as String,
  tunerId: json['tuner_id'] as String,
  number: json['number'] as String,
  numberOverride: json['number_override'] as String?,
  callsign: json['callsign'] as String,
  name: json['name'] as String,
  logoUrl: json['logo_url'] as String?,
  hd: json['hd'] as bool? ?? false,
  enabled: json['enabled'] as bool? ?? true,
  guideStationId: json['guide_station_id'] as String?,
);

/// Mirrors `LiveTvProgram` from src/api/livetv.ts.
class LiveTvProgram {
  const LiveTvProgram({
    required this.id,
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle,
    this.description,
    this.season,
    this.episode,
    this.isNew,
    this.isLive,
    this.imageUrl,
  });

  final String id;
  final String channelId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? subtitle;
  final String? description;
  final int? season;
  final int? episode;
  final bool? isNew;
  final bool? isLive;
  final String? imageUrl;

  factory LiveTvProgram.fromJson(Map<String, dynamic> json) => LiveTvProgram(
    id: json['id'] as String,
    channelId: json['channel_id'] as String,
    start: DateTime.parse(json['start'] as String),
    stop: DateTime.parse(json['stop'] as String),
    title: json['title'] as String,
    subtitle: json['subtitle'] as String?,
    description: json['description'] as String?,
    season: json['season'] as int?,
    episode: json['episode'] as int?,
    isNew: json['is_new'] as bool?,
    isLive: json['is_live'] as bool?,
    imageUrl: json['image_url'] as String?,
  );
}

enum LiveTvTransport { mpegts, hls }

/// Mirrors `LiveTvSessionStart` from src/api/livetv.ts.
class LiveTvSessionStart {
  const LiveTvSessionStart({required this.sessionId, this.playbackTicket, this.streamUrl, this.transport, this.note});

  final String sessionId;
  final String? playbackTicket;

  /// Opaque server-relative URL, played exactly as returned. It stays on the
  /// v1 media routes (`live-hls/...` or `sessions/{id}/stream`) because native
  /// players can't send v2 account auth.
  final String? streamUrl;
  final LiveTvTransport? transport;
  final String? note;

  factory LiveTvSessionStart.fromJson(Map<String, dynamic> json) => LiveTvSessionStart(
    sessionId: json['session_id'] as String,
    playbackTicket: json['playback_ticket'] as String?,
    streamUrl: json['stream_url'] as String?,
    transport: switch (json['transport'] as String?) {
      'mpegts' => LiveTvTransport.mpegts,
      'hls' => LiveTvTransport.hls,
      _ => null,
    },
    note: json['note'] as String?,
  );
}

/// Mirrors `LiveTvRecording` from src/api/livetv.ts.
class LiveTvRecording {
  const LiveTvRecording({
    required this.id,
    this.programId,
    required this.channelId,
    required this.status,
    this.start,
    this.stop,
    required this.title,
    this.libraryItemId,
  });

  final String id;
  final String? programId;
  final String channelId;
  final String status;
  final DateTime? start;
  final DateTime? stop;
  final String title;
  final String? libraryItemId;

  factory LiveTvRecording.fromJson(Map<String, dynamic> json) => LiveTvRecording(
    id: json['id'] as String,
    programId: json['program_id'] as String?,
    channelId: json['channel_id'] as String,
    status: json['status'] as String,
    start: _parseOptionalTime(json['start']),
    stop: _parseOptionalTime(json['stop']),
    title: json['title'] as String? ?? '',
    libraryItemId: json['library_item_id'] as String?,
  );
}

DateTime? _parseOptionalTime(Object? value) => value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

/// v2 lists use an `{items}` envelope.
List<Map<String, dynamic>> _items(Map<String, dynamic> json) =>
    (json['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();

/// Live TV switched off (409 `capability_not_configured`) or absent on an
/// older server (404) reads as "Live TV unavailable", not a hard failure.
bool _isLiveTvUnavailable(ApiError e) => e.status == 404 || (e.status == 409 && e.code == 'capability_not_configured');

bool _looksLikeHlsUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') || lower.contains('live-hls');
}

/// True when the session exposes an HLS stream Smart TV can play. Mirrors
/// `isWatchableHls`.
bool isWatchableHls(LiveTvSessionStart start) {
  final url = playableLiveUrl(start);
  if (url == null) return false;
  return start.transport == LiveTvTransport.hls || _looksLikeHlsUrl(url);
}

/// The session's `stream_url`, played exactly as returned (v2 dropped
/// `hls_url`). Mirrors `playableLiveUrl`.
String? playableLiveUrl(LiveTvSessionStart start) {
  final stream = (start.streamUrl ?? '').trim();
  return stream.isNotEmpty ? stream : null;
}

/// Resolves a Live TV stream for playback. Only same-origin absolute URLs
/// and relative paths (joined via [buildStreamUrl]) are allowed — raw
/// external tuner URLs must be proxied by the Prairie server. Mirrors
/// `resolveLivePlaybackUrl`.
String resolveLivePlaybackUrl(String serverUrl, String streamPath, String? token, [String? profileId]) {
  final trimmed = streamPath.trim();
  if (trimmed.isEmpty) {
    throw StateError('Live TV session returned no stream URL');
  }
  final isAbsoluteHttp = trimmed.startsWith('http://') || trimmed.startsWith('https://');
  if (isAbsoluteHttp && !isSameServerOrigin(serverUrl, trimmed)) {
    throw StateError('Live TV requires a server-proxied stream');
  }
  return buildStreamUrl(serverUrl, trimmed, token, profileId);
}

/// Mirrors `fetchLiveTvChannels`. Treats Live TV being off (409
/// `capability_not_configured`) or absent (404) as an empty list.
Future<List<LiveTvChannel>> fetchLiveTvChannels(ApiClient client, PrairieSession session) async {
  try {
    final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/livetv/channels');
    return parseLiveTvChannels(json);
  } on ApiError catch (e) {
    if (_isLiveTvUnavailable(e)) return [];
    rethrow;
  }
}

const _guideWindowGridMs = 60000;

/// Mirrors `fetchLiveTvGuide`. Guide window starts at now (snapped to a
/// minute so concurrent callers share a cache key once caching exists) and
/// spans 6 hours.
Future<List<LiveTvProgram>> fetchLiveTvGuide(ApiClient client, PrairieSession session, List<String> channelIds) async {
  if (channelIds.isEmpty) return [];
  final nowMs = (DateTime.now().millisecondsSinceEpoch ~/ _guideWindowGridMs) * _guideWindowGridMs;
  final start = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  final end = DateTime.fromMillisecondsSinceEpoch(nowMs + 6 * 60 * 60 * 1000, isUtc: true);
  // v2 repeats `channel_id` once per channel (max 500), not a comma list.
  final params = <String, dynamic>{
    'channel_id': channelIds.take(500).toList(),
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/livetv/guide?${Uri(queryParameters: params).query}',
  );
  return _items(json).map(LiveTvProgram.fromJson).toList();
}

/// Enabled channels from a v2 `{items}` channel list.
List<LiveTvChannel> parseLiveTvChannels(Map<String, dynamic> json) =>
    _items(json).map(_channelFromJson).where((ch) => ch.enabled).toList();

/// Mirrors `startLiveTvSession` (201; 409 when no tuner is free). The
/// optional `client_capabilities` body isn't sent.
Future<LiveTvSessionStart> startLiveTvSession(ApiClient client, PrairieSession session, String channelId) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/livetv/channels/${Uri.encodeComponent(channelId)}/sessions',
    method: 'POST',
    body: '{}',
  );
  return LiveTvSessionStart.fromJson(json);
}

/// Mirrors `releaseLiveTvSession` (204, no body).
Future<void> releaseLiveTvSession(ApiClient client, PrairieSession session, String liveSessionId) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v2/livetv/sessions/${Uri.encodeComponent(liveSessionId)}',
  method: 'DELETE',
);

/// How often an open live player checks in; mirrors web's
/// LIVETV_HEARTBEAT_INTERVAL_MS. The server reclaims a tuner after ~90s
/// without a heartbeat, and a paused player stops fetching segments.
const liveTvHeartbeatInterval = Duration(seconds: 30);

/// Mirrors `useLiveTVSessionHeartbeat`: `POST /livetv/sessions/{id}/heartbeat`
/// (no body, 204) keeps the live session's tuner claimed.
Future<void> heartbeatLiveTvSession(ApiClient client, PrairieSession session, String liveSessionId) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v2/livetv/sessions/${Uri.encodeComponent(liveSessionId)}/heartbeat',
  method: 'POST',
);

/// Mirrors `fetchLiveTvRecordings`, also treating Live TV off/absent as empty.
Future<List<LiveTvRecording>> fetchLiveTvRecordings(ApiClient client, PrairieSession session) async {
  try {
    final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/livetv/recordings');
    return _items(json).map(LiveTvRecording.fromJson).toList();
  } on ApiError catch (e) {
    if (_isLiveTvUnavailable(e)) return [];
    rethrow;
  }
}

/// Mirrors `scheduleLiveTvRecording`.
Future<LiveTvRecording> scheduleLiveTvRecording(ApiClient client, PrairieSession session, String programId) async {
  final trimmed = programId.trim();
  if (trimmed.isEmpty) throw ArgumentError('Missing program id');
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/livetv/recordings',
    method: 'POST',
    body: {'program_id': trimmed},
  );
  return LiveTvRecording.fromJson(json);
}

/// Mirrors `cancelLiveTvRecording`.
Future<void> cancelLiveTvRecording(ApiClient client, PrairieSession session, String recordingId) {
  final trimmed = recordingId.trim();
  if (trimmed.isEmpty) throw ArgumentError('Missing recording id');
  return client.request<dynamic>(
    _sessionOptions(session),
    '/api/v2/livetv/recordings/${Uri.encodeComponent(trimmed)}',
    method: 'DELETE',
  );
}

/// Mirrors `channelDisplayLabel`.
String channelDisplayLabel(LiveTvChannel channel) {
  final name = channel.name.trim().isNotEmpty ? channel.name.trim() : channel.callsign.trim();
  return name.isNotEmpty ? name : 'Channel ${channel.numberOverride ?? channel.number}';
}

/// Guide entries grouped by channel and sorted by start time. Mirrors
/// `indexProgramsByChannel`.
Map<String, List<LiveTvProgram>> indexProgramsByChannel(List<LiveTvProgram> programs) {
  final index = <String, List<LiveTvProgram>>{};
  for (final program in programs) {
    index.putIfAbsent(program.channelId, () => []).add(program);
  }
  for (final list in index.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return index;
}

/// Picks the program airing "now" for a channel from a prebuilt index.
/// Mirrors `currentProgramInIndex`.
LiveTvProgram? currentProgramInIndex(Map<String, List<LiveTvProgram>> index, String channelId, [DateTime? now]) {
  final nowTime = now ?? DateTime.now();
  for (final program in index[channelId] ?? const <LiveTvProgram>[]) {
    if (!program.start.isAfter(nowTime) && program.stop.isAfter(nowTime)) return program;
  }
  return null;
}

/// Picks the next upcoming program after "now". Mirrors `nextProgramInIndex`.
LiveTvProgram? nextProgramInIndex(Map<String, List<LiveTvProgram>> index, String channelId, [DateTime? now]) {
  final nowTime = now ?? DateTime.now();
  for (final program in index[channelId] ?? const <LiveTvProgram>[]) {
    if (program.start.isAfter(nowTime)) return program;
  }
  return null;
}

/// Fraction of the current programme that has already aired (0-1). Mirrors
/// `programProgressFraction`.
double programProgressFraction(DateTime start, DateTime stop, [DateTime? now]) {
  final nowTime = now ?? DateTime.now();
  final total = stop.difference(start).inMilliseconds;
  if (total <= 0) return 0;
  final elapsed = nowTime.difference(start).inMilliseconds;
  return elapsed.clamp(0, total) / total;
}
