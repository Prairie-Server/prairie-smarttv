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
  streamUrl: json['stream_url'] as String?,
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
  const LiveTvSessionStart({required this.sessionId, this.playbackTicket, this.hlsUrl, this.streamUrl, this.transport, this.note});

  final String sessionId;
  final String? playbackTicket;
  final String? hlsUrl;
  final String? streamUrl;
  final LiveTvTransport? transport;
  final String? note;

  factory LiveTvSessionStart.fromJson(Map<String, dynamic> json) => LiveTvSessionStart(
    sessionId: json['session_id'] as String,
    playbackTicket: json['playback_ticket'] as String?,
    hlsUrl: json['hls_url'] as String?,
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
    required this.start,
    required this.stop,
    required this.title,
    this.libraryItemId,
  });

  final String id;
  final String? programId;
  final String channelId;
  final String status;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? libraryItemId;

  factory LiveTvRecording.fromJson(Map<String, dynamic> json) => LiveTvRecording(
    id: json['id'] as String,
    programId: json['program_id'] as String?,
    channelId: json['channel_id'] as String,
    status: json['status'] as String,
    start: DateTime.parse(json['start'] as String),
    stop: DateTime.parse(json['stop'] as String),
    title: json['title'] as String,
    libraryItemId: json['library_item_id'] as String?,
  );
}

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

/// Prefers HLS URLs; MPEG-TS proxy paths are returned only when no HLS is
/// available. Mirrors `playableLiveUrl`.
String? playableLiveUrl(LiveTvSessionStart start) {
  final hls = (start.hlsUrl ?? '').trim();
  final stream = (start.streamUrl ?? '').trim();

  if (start.transport == LiveTvTransport.hls) {
    return hls.isNotEmpty ? hls : (stream.isNotEmpty ? stream : null);
  }

  if (hls.isNotEmpty && _looksLikeHlsUrl(hls)) return hls;
  if (stream.isNotEmpty && _looksLikeHlsUrl(stream)) return stream;
  if (hls.isNotEmpty) return hls;
  if (start.transport == LiveTvTransport.mpegts) {
    return stream.isNotEmpty ? stream : null;
  }
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

/// Mirrors `fetchLiveTvChannels`. Treats a 404 (feature absent on older
/// servers) as an empty list rather than a hard failure.
Future<List<LiveTvChannel>> fetchLiveTvChannels(ApiClient client, PrairieSession session) async {
  try {
    final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v1/livetv/channels');
    final channels = (json['channels'] as List<dynamic>? ?? []).map((j) => _channelFromJson(j as Map<String, dynamic>));
    return channels.where((ch) => ch.enabled).toList();
  } on ApiError catch (e) {
    if (e.status == 404) return [];
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
  final params = {
    'channels': channelIds.join(','),
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/livetv/guide?${Uri(queryParameters: params).query}',
  );
  return (json['programs'] as List<dynamic>? ?? []).map((j) => LiveTvProgram.fromJson(j as Map<String, dynamic>)).toList();
}

/// Mirrors `startLiveTvSession`.
Future<LiveTvSessionStart> startLiveTvSession(ApiClient client, PrairieSession session, String channelId) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/livetv/channels/${Uri.encodeComponent(channelId)}/session',
    method: 'POST',
    body: '{}',
  );
  return LiveTvSessionStart.fromJson(json);
}

/// Mirrors `releaseLiveTvSession`.
Future<void> releaseLiveTvSession(ApiClient client, PrairieSession session, String liveSessionId) => client.request<dynamic>(
  _sessionOptions(session),
  '/api/v1/livetv/sessions/${Uri.encodeComponent(liveSessionId)}',
  method: 'DELETE',
);

/// Mirrors `fetchLiveTvRecordings`, also treating 404 as empty.
Future<List<LiveTvRecording>> fetchLiveTvRecordings(ApiClient client, PrairieSession session) async {
  try {
    final json = await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v1/livetv/recordings');
    return (json['recordings'] as List<dynamic>? ?? []).map((j) => LiveTvRecording.fromJson(j as Map<String, dynamic>)).toList();
  } on ApiError catch (e) {
    if (e.status == 404) return [];
    rethrow;
  }
}

/// Mirrors `scheduleLiveTvRecording`.
Future<LiveTvRecording> scheduleLiveTvRecording(ApiClient client, PrairieSession session, String programId) async {
  final trimmed = programId.trim();
  if (trimmed.isEmpty) throw ArgumentError('Missing program id');
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v1/livetv/recordings',
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
    '/api/v1/livetv/recordings/${Uri.encodeComponent(trimmed)}',
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
