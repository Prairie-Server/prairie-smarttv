import 'package:prairie_core/src/api/api_client.dart';
import 'package:prairie_core/src/api/api_error.dart';
import 'package:prairie_core/src/models/auth.dart';

ApiClientOptions _sessionOptions(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// Whether this server plays theme music for the viewer
/// (`GET /api/v2/catalog/themes/capabilities`, v2 `ThemeSongsCapability`).
class ThemeMusicCapability {
  const ThemeMusicCapability({required this.state, required this.allowed});

  /// `available`, `disabled`, `not_configured` or `unsupported`.
  final String state;
  final bool allowed;

  bool get available => state == 'available' && allowed;

  factory ThemeMusicCapability.fromJson(Map<String, dynamic> json) =>
      ThemeMusicCapability(state: json['state'] as String? ?? '', allowed: json['allowed'] == true);
}

/// Servers from before theme music answer 404: they have none to play.
Future<ThemeMusicCapability> fetchThemeMusicCapability(ApiClient client, PrairieSession session) async {
  try {
    return ThemeMusicCapability.fromJson(
      await client.request<Map<String, dynamic>>(_sessionOptions(session), '/api/v2/catalog/themes/capabilities'),
    );
  } on ApiError catch (e) {
    if (e.status == 404) return const ThemeMusicCapability(state: 'unsupported', allowed: false);
    rethrow;
  }
}

/// A short-lived grant to stream one theme (v2 `ThemePlayback`). [url] is a
/// credential: never log or keep it.
class ThemeMusicGrant {
  const ThemeMusicGrant({required this.url, required this.converted, required this.contentType});

  /// Absolute: a relative grant is resolved against the server.
  final String url;

  /// Converted audio is a progressive AAC stream without byte ranges. It
  /// can't seek back, so replaying it takes a new grant.
  final bool converted;
  final String contentType;
}

/// The audio containers and codecs the TV's media pipeline plays. A theme in
/// any other format is converted to AAC in MP4 by the server.
const themeMusicAcceptedFormats = [
  {'container': 'mp3', 'audio_codec': 'mp3'},
  {'container': 'mp4', 'audio_codec': 'aac'},
  {'container': 'm4a', 'audio_codec': 'aac'},
];

/// `POST /api/v2/catalog/items/{owner}/themes/{theme}/playback`.
Future<ThemeMusicGrant> requestThemeMusic(
  ApiClient client,
  PrairieSession session, {
  required String ownerId,
  required String themeId,
}) async {
  final json = await client.request<Map<String, dynamic>>(
    _sessionOptions(session),
    '/api/v2/catalog/items/${Uri.encodeComponent(ownerId)}/themes/${Uri.encodeComponent(themeId)}/playback',
    method: 'POST',
    body: {'accepted_formats': themeMusicAcceptedFormats},
  );
  final url = json['url'] as String? ?? '';
  if (url.isEmpty) throw ApiError('The server sent no theme audio', 0);
  return ThemeMusicGrant(
    url: Uri.parse(session.serverUrl).resolve(url).toString(),
    converted: json['delivery'] == 'converted',
    contentType: json['content_type'] as String? ?? '',
  );
}

/// The profile's theme music preferences on this TV: `ui.theme_music_enabled`
/// and `ui.theme_music_loop`, both off by default.
class ThemeMusicSettings {
  const ThemeMusicSettings({this.enabled = false, this.loop = false});

  final bool enabled;
  final bool loop;

  static const enabledKey = 'ui.theme_music_enabled';
  static const loopKey = 'ui.theme_music_loop';

  factory ThemeMusicSettings.fromValues(Map<String, Object?> values) =>
      ThemeMusicSettings(enabled: values[enabledKey] == true, loop: values[loopKey] == true);
}

/// Reads both keys from the effective settings. A server that doesn't know
/// them answers 422, which reads as null so the toggles stay hidden.
Future<ThemeMusicSettings?> fetchThemeMusicSettings(ApiClient client, PrairieSession session) async {
  const keys = [ThemeMusicSettings.enabledKey, ThemeMusicSettings.loopKey];
  // Repeated `keys=` params: v2 reads a comma as part of the key name.
  final query = keys.map((k) => 'keys=${Uri.encodeQueryComponent(k)}').join('&');
  try {
    final data = await client.request<dynamic>(_sessionOptions(session), '/api/v2/settings/values/effective?$query');
    final items = data is Map ? data['items'] : null;
    return ThemeMusicSettings.fromValues({
      if (items is List)
        for (final item in items)
          if (item is Map && item['key'] is String) item['key'] as String: item['value'],
    });
  } on ApiError catch (e) {
    if (e.status == 422 || e.status == 404) return null;
    rethrow;
  }
}

/// Saves one theme music key for this profile on this TV, as Apple TV does,
/// since music can suit one screen and not another.
Future<void> saveThemeMusicSetting(ApiClient client, PrairieSession session, String key, bool value) =>
    client.request<dynamic>(
      _sessionOptions(session),
      '/api/v2/settings/values/${Uri.encodeComponent(key)}?scope=profile_device',
      method: 'PUT',
      body: {'value': value},
    );
