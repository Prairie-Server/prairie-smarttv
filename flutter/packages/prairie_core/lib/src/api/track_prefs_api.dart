import '../models/auth.dart';
import '../models/watch_detail.dart';
import '../player/track_choice.dart';
import 'api_client.dart';

ApiClientOptions _options(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Remembers a subtitle pick for every episode of [seriesId]
/// (`PUT /api/v2/subtitle-prefs/{series_id}`); see [subtitlePreferenceBody].
/// [track] null with an empty [language] remembers Off.
Future<void> saveSeriesSubtitlePreference(
  ApiClient client,
  PrairieSession session,
  String seriesId, {
  SubtitleTrackInfo? track,
  int? trackIndex,
  String? language,
}) => client.request<dynamic>(
  _options(session),
  '/api/v2/subtitle-prefs/${Uri.encodeComponent(seriesId)}',
  method: 'PUT',
  body: subtitlePreferenceBody(track: track, trackIndex: trackIndex, language: language),
);

/// Remembers an audio pick for every episode of [seriesId]
/// (`PUT /api/v2/audio-prefs/{series_id}`).
Future<void> saveSeriesAudioPreference(
  ApiClient client,
  PrairieSession session,
  String seriesId,
  int index,
  AudioTrackInfo? track,
) => client.request<dynamic>(
  _options(session),
  '/api/v2/audio-prefs/${Uri.encodeComponent(seriesId)}',
  method: 'PUT',
  body: audioPreferenceBody(index, track),
);
