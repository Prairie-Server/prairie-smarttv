import '../api/api_client.dart';
import '../api/api_error.dart';
import '../models/auth.dart';

/// `playback.intro_skip_mode`.
enum IntroSkipMode { never, ask, always }

/// The profile's server-side skip/autoplay preferences, resolved
/// `profile_device > profile > default`. Defaults match the settings
/// manifest.
class PlaybackSkipSettings {
  const PlaybackSkipSettings({
    this.introSkipMode = IntroSkipMode.ask,
    this.autoSkipRecap = false,
    this.autoSkipCredits = false,
    this.autoPlayNext = true,
    this.autoPlayNextPreview = false,
  });

  final IntroSkipMode introSkipMode;
  final bool autoSkipRecap;
  final bool autoSkipCredits;
  final bool autoPlayNext;

  /// Start the up-next countdown at a trailing next-episode preview too, not
  /// only at the credits (web `resolveAutoplayMarker`'s `allowPreview`).
  final bool autoPlayNextPreview;

  static const introSkipModeKey = 'playback.intro_skip_mode';
  static const autoSkipRecapKey = 'playback.auto_skip_recap';
  static const autoSkipCreditsKey = 'playback.auto_skip_credits';
  static const autoPlayNextKey = 'playback.auto_play_next';
  static const autoPlayNextPreviewKey = 'playback.auto_play_next_preview';

  /// Deprecated boolean the enum replaced; servers before settings contract
  /// revision 7 only know this one (`true` = always, `false` = ask).
  static const legacyAutoSkipIntroKey = 'playback.auto_skip_intro';

  PlaybackSkipSettings copyWith({
    IntroSkipMode? introSkipMode,
    bool? autoSkipRecap,
    bool? autoSkipCredits,
    bool? autoPlayNext,
    bool? autoPlayNextPreview,
  }) => PlaybackSkipSettings(
    introSkipMode: introSkipMode ?? this.introSkipMode,
    autoSkipRecap: autoSkipRecap ?? this.autoSkipRecap,
    autoSkipCredits: autoSkipCredits ?? this.autoSkipCredits,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    autoPlayNextPreview: autoPlayNextPreview ?? this.autoPlayNextPreview,
  );

  /// From a key → value map of effective settings; missing keys keep defaults.
  factory PlaybackSkipSettings.fromValues(Map<String, Object?> values) {
    const d = PlaybackSkipSettings();
    final mode = values[introSkipModeKey];
    final legacy = values[legacyAutoSkipIntroKey];
    return PlaybackSkipSettings(
      introSkipMode: IntroSkipMode.values.where((m) => m.name == mode).firstOrNull ??
          (legacy is bool ? (legacy ? IntroSkipMode.always : IntroSkipMode.ask) : d.introSkipMode),
      autoSkipRecap: _bool(values[autoSkipRecapKey], d.autoSkipRecap),
      autoSkipCredits: _bool(values[autoSkipCreditsKey], d.autoSkipCredits),
      autoPlayNext: _bool(values[autoPlayNextKey], d.autoPlayNext),
      autoPlayNextPreview: _bool(values[autoPlayNextPreviewKey], d.autoPlayNextPreview),
    );
  }

  static bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;
}

ApiClientOptions _options(PrairieSession session) => ApiClientOptions(
  serverUrl: session.serverUrl,
  accessToken: session.accessToken,
  refreshToken: session.refreshToken,
  profileId: session.profileId,
  profileToken: session.profileToken,
);

/// v2 `listEffectiveSettings` for the skip/autoplay keys. An unknown key is a
/// 422 for the whole read, so a server without `intro_skip_mode` is retried
/// with the legacy boolean in its place.
Future<PlaybackSkipSettings> fetchPlaybackSkipSettings(ApiClient client, PrairieSession session) async {
  const rest = [
    PlaybackSkipSettings.autoSkipRecapKey,
    PlaybackSkipSettings.autoSkipCreditsKey,
    PlaybackSkipSettings.autoPlayNextKey,
    PlaybackSkipSettings.autoPlayNextPreviewKey,
  ];
  try {
    return PlaybackSkipSettings.fromValues(
      await _effectiveValues(client, session, [PlaybackSkipSettings.introSkipModeKey, ...rest]),
    );
  } on ApiError catch (e) {
    if (e.status != 422) rethrow;
    return PlaybackSkipSettings.fromValues(
      await _effectiveValues(client, session, [PlaybackSkipSettings.legacyAutoSkipIntroKey, ...rest]),
    );
  }
}

Future<Map<String, Object?>> _effectiveValues(ApiClient client, PrairieSession session, List<String> keys) async {
  // Repeated `keys=` params: v2 reads a comma as part of the key name.
  final query = keys.map((k) => 'keys=${Uri.encodeQueryComponent(k)}').join('&');
  final data = await client.request<dynamic>(_options(session), '/api/v2/settings/values/effective?$query');
  final items = data is Map ? data['items'] : null;
  return {
    if (items is List)
      for (final item in items)
        if (item is Map && item['key'] is String) item['key'] as String: item['value'],
  };
}

/// Stores [value] for the profile, then clears this device's override so it
/// cannot shadow the profile-wide choice (web `autoPlayNext.ts` does the
/// same). The intro mode falls back to the legacy boolean on old servers.
Future<void> savePlaybackSkipSetting(ApiClient client, PrairieSession session, String key, Object value) async {
  try {
    await _put(client, session, key, value);
  } on ApiError catch (e) {
    if (e.status != 422 || key != PlaybackSkipSettings.introSkipModeKey) rethrow;
    key = PlaybackSkipSettings.legacyAutoSkipIntroKey;
    await _put(client, session, key, value == IntroSkipMode.always.name);
  }
  try {
    await client.request<dynamic>(
      _options(session),
      '/api/v2/settings/values/${Uri.encodeComponent(key)}?scope=profile_device',
      method: 'DELETE',
    );
  } on ApiError {
    // 404 when there was no device row — the common case.
  }
}

Future<void> _put(ApiClient client, PrairieSession session, String key, Object value) => client.request<dynamic>(
  _options(session),
  '/api/v2/settings/values/${Uri.encodeComponent(key)}?scope=profile',
  method: 'PUT',
  body: {'value': value},
);
