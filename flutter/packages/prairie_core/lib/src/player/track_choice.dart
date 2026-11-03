import '../lib/language_labels.dart';
import '../models/watch_detail.dart';

/// Whether two track language strings name the same language: `eng`, `en`,
/// `en-US` and `English` all match. Empty never matches.
bool sameTrackLanguage(String? a, String? b) {
  final x = (a ?? '').trim().toLowerCase();
  final y = (b ?? '').trim().toLowerCase();
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final named = humanizeTrackLanguage(x);
  return named != 'Unknown' && named == humanizeTrackLanguage(y);
}

/// A subtitle track the server says it can't show. Uses the server's
/// `unplayable` flag; an older server that omits it stores an embedded track
/// it can't read with no codec, so an embedded row without one counts too.
/// External (downloaded) tracks can arrive without a codec and still play.
bool isUnplayableSubtitle(SubtitleTrackInfo track) {
  final flag = track.unplayable;
  if (flag != null) return flag;
  return track.external != true && (track.codec ?? '').trim().isEmpty;
}

/// The subtitle language to turn on when playback starts; `''` means off.
///
/// In order:
/// 1. an explicit pick carried by the launch ([launchChoice], `''` = Off) —
///    from the detail page, or the viewer's pick handed to the next episode;
/// 2. a remembered per-series choice: [preferenceMode] `off` stays off and
///    `always` turns on [preferenceLanguage];
/// 3. this TV's own preferred subtitle language setting ([deviceLanguage]);
/// 4. `auto` with a language: on only when it differs from [audioLanguage].
///
/// A language whose every matching server track is unplayable
/// ([isUnplayableSubtitle]) is never auto-picked: the result is off.
String resolveStartSubtitleLanguage({
  String? launchChoice,
  String? preferenceMode,
  String? preferenceLanguage,
  String deviceLanguage = '',
  String? audioLanguage,
  List<SubtitleTrackInfo> serverTracks = const [],
}) {
  if (launchChoice != null) return launchChoice.trim();
  final mode = (preferenceMode ?? '').trim().toLowerCase();
  final language = (preferenceLanguage ?? '').trim();
  final device = deviceLanguage.trim();
  String chosen;
  if (mode == 'off') {
    chosen = '';
  } else if (mode == 'always' && language.isNotEmpty) {
    chosen = language;
  } else if (device.isNotEmpty) {
    chosen = device;
  } else if (mode == 'auto' && language.isNotEmpty && !sameTrackLanguage(language, audioLanguage)) {
    chosen = language;
  } else {
    chosen = '';
  }
  if (chosen.isEmpty || !onlyUnplayableSubtitlesFor(chosen, serverTracks)) return chosen;
  return '';
}

/// True when [serverTracks] has tracks in [language] and the server can't
/// show any of them.
bool onlyUnplayableSubtitlesFor(String language, List<SubtitleTrackInfo> serverTracks) {
  var matched = false;
  for (final track in serverTracks) {
    if (!sameTrackLanguage(track.language, language)) continue;
    if (!isUnplayableSubtitle(track)) return false;
    matched = true;
  }
  return matched;
}

/// The server subtitle track a native-player pick in [language] stands for:
/// a showable, non-forced track in that language, else any showable one.
/// Returns its position in [serverTracks], or null when none matches.
int? matchServerSubtitleTrack(List<SubtitleTrackInfo> serverTracks, String language) {
  int? fallback;
  for (var i = 0; i < serverTracks.length; i++) {
    final track = serverTracks[i];
    if (isUnplayableSubtitle(track) || !sameTrackLanguage(track.language, language)) continue;
    if (track.forced != true) return i;
    fallback ??= i;
  }
  return fallback;
}

/// The audio track to request at start: an explicit launch pick, else the
/// remembered/effective track when it is a deliberate non-default choice,
/// else [playableFallback] (a decodable alternative to an undecodable
/// default, or null to let the server choose).
int? resolveStartAudioTrackIndex({
  int? launchIndex,
  int? effectiveIndex,
  required List<AudioTrackInfo> tracks,
  int? playableFallback,
}) {
  if (launchIndex != null) return launchIndex;
  if (effectiveIndex != null && effectiveIndex >= 0 && effectiveIndex < tracks.length) {
    var defaultIndex = tracks.indexWhere((t) => t.isDefault == true);
    if (defaultIndex < 0) defaultIndex = 0;
    if (effectiveIndex != defaultIndex) return effectiveIndex;
  }
  return playableFallback;
}

/// `PUT /api/v2/subtitle-prefs/{series_id}` body for a pick: [track] at
/// [trackIndex] turns subtitles on in its language (mode `always`); null
/// turns them off. Never carries `show_forced_subtitles`: a present value is
/// stored as a deliberate series override of the profile's forced-subtitle
/// setting, and a track pick must not pin it.
Map<String, Object> subtitlePreferenceBody({SubtitleTrackInfo? track, int? trackIndex, String? language}) {
  final lang = (track?.language ?? language ?? '').trim();
  if (track == null && lang.isEmpty) {
    return {'subtitle_track_index': -1, 'subtitle_language': '', 'subtitle_mode': 'off'};
  }
  final index = track?.index ?? trackIndex ?? 0;
  final signature = <String, Object>{
    if (lang.isNotEmpty) 'language': lang,
    if ((track?.codec ?? '').isNotEmpty) 'codec': track!.codec!,
    if ((track?.title ?? '').isNotEmpty) 'label': track!.title!,
    if (track?.forced != null) 'forced': track!.forced!,
    if (track?.hearingImpaired != null) 'hearing_impaired': track!.hearingImpaired!,
    if (track != null) 'source': track.external == true ? 'external' : 'embedded',
  };
  return {
    'subtitle_track_index': index < -1 ? -1 : index,
    'subtitle_language': lang,
    'subtitle_mode': 'always',
    if (signature.isNotEmpty) 'track_signature': signature,
  };
}

/// `PUT /api/v2/audio-prefs/{series_id}` body for picking [track] at [index].
Map<String, Object> audioPreferenceBody(int index, AudioTrackInfo? track) {
  final language = (track?.language ?? '').trim();
  final signature = <String, Object>{
    if (language.isNotEmpty) 'language': language,
    if ((track?.codec ?? '').isNotEmpty) 'codec': track!.codec!,
    if (track?.channels != null) 'channels': track!.channels!,
    if (track?.isDefault != null) 'default': track!.isDefault!,
    if ((track?.title ?? '').isNotEmpty) 'title': track!.title!,
    if ((track?.embeddedTitle ?? '').isNotEmpty) 'embedded_title': track!.embeddedTitle!,
  };
  return {
    'audio_track_index': index,
    'audio_language': language,
    if (signature.isNotEmpty) 'track_signature': signature,
  };
}
