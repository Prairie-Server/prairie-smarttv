import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'subtitle_appearance.dart';

/// Mirrors src/settings/playbackSettings.ts. `playerBackend` isn't ported —
/// that TS field chose between a web `<video>` element and a native player;
/// Flutter has exactly one native [VideoBackend] per platform, so there's no
/// runtime choice to make.
class PlaybackSettings {
  const PlaybackSettings({
    this.forceDirectPlay = false,
    this.forceTranscode = false,
    this.forceAv1 = false,
    this.disableAv1 = false,
    this.subtitleAppearance = const SubtitleAppearance(),
    this.preferredSubtitleLanguage = '',
    this.enableDiagnosticsBeacon = false,
  });

  final bool forceDirectPlay;
  final bool forceTranscode;
  final bool forceAv1;
  final bool disableAv1;
  final SubtitleAppearance subtitleAppearance;
  final String preferredSubtitleLanguage;
  /// Off by default — sends player-state beacons (see `VideoholeVideoBackend`)
  /// on every playback session, which is extra network traffic in normal use
  /// and only useful while actively diagnosing a TV playback issue.
  final bool enableDiagnosticsBeacon;

  PlaybackSettings copyWith({
    bool? forceDirectPlay,
    bool? forceTranscode,
    bool? forceAv1,
    bool? disableAv1,
    SubtitleAppearance? subtitleAppearance,
    String? preferredSubtitleLanguage,
    bool? enableDiagnosticsBeacon,
  }) {
    var next = PlaybackSettings(
      forceDirectPlay: forceDirectPlay ?? this.forceDirectPlay,
      forceTranscode: forceTranscode ?? this.forceTranscode,
      forceAv1: forceAv1 ?? this.forceAv1,
      disableAv1: disableAv1 ?? this.disableAv1,
      subtitleAppearance: subtitleAppearance ?? this.subtitleAppearance,
      preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      enableDiagnosticsBeacon: enableDiagnosticsBeacon ?? this.enableDiagnosticsBeacon,
    );
    // Direct wins when both are somehow set; disable wins over force av1.
    if (next.forceDirectPlay && next.forceTranscode) next = next.copyWithRaw(forceTranscode: false);
    if (next.forceAv1 && next.disableAv1) next = next.copyWithRaw(forceAv1: false);
    return next;
  }

  PlaybackSettings copyWithRaw({bool? forceDirectPlay, bool? forceTranscode, bool? forceAv1}) => PlaybackSettings(
    forceDirectPlay: forceDirectPlay ?? this.forceDirectPlay,
    forceTranscode: forceTranscode ?? this.forceTranscode,
    forceAv1: forceAv1 ?? this.forceAv1,
    disableAv1: disableAv1,
    subtitleAppearance: subtitleAppearance,
    preferredSubtitleLanguage: preferredSubtitleLanguage,
    enableDiagnosticsBeacon: enableDiagnosticsBeacon,
  );

  Map<String, dynamic> toJson() => {
    'forceDirectPlay': forceDirectPlay,
    'forceTranscode': forceTranscode,
    'forceAv1': forceAv1,
    'disableAv1': disableAv1,
    'subtitleAppearance': subtitleAppearance.toJson(),
    'preferredSubtitleLanguage': preferredSubtitleLanguage,
    'enableDiagnosticsBeacon': enableDiagnosticsBeacon,
  };

  factory PlaybackSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlaybackSettings();
    return PlaybackSettings(
      forceDirectPlay: json['forceDirectPlay'] == true,
      forceTranscode: json['forceTranscode'] == true,
      forceAv1: json['forceAv1'] == true,
      disableAv1: json['disableAv1'] == true,
      subtitleAppearance: SubtitleAppearance.fromJson(json['subtitleAppearance'] as Map<String, dynamic>?),
      preferredSubtitleLanguage: (json['preferredSubtitleLanguage'] as String?)?.trim().toLowerCase() ?? '',
      enableDiagnosticsBeacon: json['enableDiagnosticsBeacon'] == true,
    );
  }
}

/// Stable key matching TS `prairie.playbackSettings`. Legacy Flutter key
/// `prairie.settings.playback` is read as a fallback and migrated on save /
/// via [DurableStore.ensureStorageSchema].
const playbackSettingsKey = 'prairie.playbackSettings';
const legacyPlaybackSettingsKey = 'prairie.settings.playback';

Future<PlaybackSettings> loadPlaybackSettings(SharedPreferencesAsync prefs) async {
  var raw = await prefs.getString(playbackSettingsKey);
  if (raw == null || raw.isEmpty) {
    raw = await prefs.getString(legacyPlaybackSettingsKey);
  }
  if (raw == null) return const PlaybackSettings();
  try {
    return PlaybackSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const PlaybackSettings();
  }
}

Future<PlaybackSettings> savePlaybackSettings(PlaybackSettings settings, SharedPreferencesAsync prefs) async {
  await prefs.setString(playbackSettingsKey, jsonEncode(settings.toJson()));
  return settings;
}

/// Mirrors `resolveForcedPlayMethod`/`describePlayMethodPreference`.
String? resolveForcedPlayMethod(PlaybackSettings settings) {
  if (settings.forceDirectPlay) return 'direct';
  if (settings.forceTranscode) return 'transcode';
  return null;
}
