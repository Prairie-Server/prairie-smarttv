/// Mirrors `AudioTrackInfo` from src/api/watch.ts.
class AudioTrackInfo {
  const AudioTrackInfo({this.title, this.embeddedTitle, this.language, this.codec, this.channels, this.isDefault});
  final String? title;
  final String? embeddedTitle;
  final String? language;
  final String? codec;
  final int? channels;
  final bool? isDefault;

  factory AudioTrackInfo.fromJson(Map<String, dynamic> json) => AudioTrackInfo(
    title: json['title'] as String?,
    embeddedTitle: json['embedded_title'] as String?,
    language: json['language'] as String?,
    codec: json['codec'] as String?,
    channels: json['channels'] as int?,
    isDefault: json['default'] as bool?,
  );
}

/// Minimal video-track fields from the watch/detail `video_tracks` payload —
/// enough for native-plane aspect layout when the player reports 0×0 size.
class VideoTrackInfo {
  const VideoTrackInfo({this.width, this.height, this.aspectRatio});

  final int? width;
  final int? height;
  /// Probed display ratio string, e.g. `"16:9"`, `"2.39:1"`, `"239:100"`.
  final String? aspectRatio;

  factory VideoTrackInfo.fromJson(Map<String, dynamic> json) => VideoTrackInfo(
    width: json['width'] as int?,
    height: json['height'] as int?,
    aspectRatio: json['aspect_ratio'] as String?,
  );
}

/// Display aspect from a probed [VideoTrackInfo], preferring pixel dimensions
/// (exact) over the rounded `aspect_ratio` string.
double? contentAspectRatioFromVideoTrack(VideoTrackInfo? track) {
  if (track == null) return null;
  final w = track.width;
  final h = track.height;
  if (w != null && h != null && w > 0 && h > 0) return w / h;
  return parseAspectRatioString(track.aspectRatio);
}

/// Parses `"16:9"` / `"2.39:1"` / `"239:100"` into a width÷height double.
double? parseAspectRatioString(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length != 2) return null;
  final num = double.tryParse(parts[0].trim());
  final den = double.tryParse(parts[1].trim());
  if (num == null || den == null || den == 0) return null;
  final ratio = num / den;
  return ratio > 0 ? ratio : null;
}

/// First video track's aspect for [fileId], or null when unknown.
double? contentAspectRatioForFile(WatchDetail? detail, int fileId) {
  if (detail == null) return null;
  FileVersion? version;
  for (final v in detail.versions) {
    if (v.fileId == fileId) {
      version = v;
      break;
    }
  }
  version ??= detail.versions.isNotEmpty ? detail.versions.first : null;
  if (version == null || version.videoTracks.isEmpty) return null;
  return contentAspectRatioFromVideoTrack(version.videoTracks.first);
}

/// Mirrors `SubtitleTrackInfo` from src/api/watch.ts.
class SubtitleTrackInfo {
  const SubtitleTrackInfo({
    this.index,
    this.language,
    this.codec,
    this.title,
    this.forced,
    this.isDefault,
    this.hearingImpaired,
    this.external,
  });

  final int? index;
  final String? language;
  final String? codec;
  final String? title;
  final bool? forced;
  final bool? isDefault;
  final bool? hearingImpaired;
  final bool? external;

  factory SubtitleTrackInfo.fromJson(Map<String, dynamic> json) => SubtitleTrackInfo(
    index: json['index'] as int?,
    language: json['language'] as String?,
    codec: json['codec'] as String?,
    title: json['title'] as String?,
    forced: json['forced'] as bool?,
    isDefault: json['default'] as bool?,
    hearingImpaired: json['hearing_impaired'] as bool?,
    external: json['external'] as bool?,
  );
}

/// Mirrors `FileVersion` from src/api/watch.ts.
class FileVersion {
  const FileVersion({
    required this.fileId,
    this.resolution,
    this.codecVideo,
    this.codecAudio,
    this.container,
    this.duration,
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
  });

  final int fileId;
  final String? resolution;
  final String? codecVideo;
  final String? codecAudio;
  final String? container;
  final int? duration;
  final List<VideoTrackInfo> videoTracks;
  final List<AudioTrackInfo> audioTracks;
  final List<SubtitleTrackInfo> subtitleTracks;

  factory FileVersion.fromJson(Map<String, dynamic> json) => FileVersion(
    fileId: json['file_id'] as int,
    resolution: json['resolution'] as String?,
    codecVideo: json['codec_video'] as String?,
    codecAudio: json['codec_audio'] as String?,
    container: json['container'] as String?,
    duration: json['duration'] as int?,
    videoTracks: (json['video_tracks'] as List<dynamic>? ?? []).map((j) => VideoTrackInfo.fromJson(j as Map<String, dynamic>)).toList(),
    audioTracks: (json['audio_tracks'] as List<dynamic>? ?? []).map((j) => AudioTrackInfo.fromJson(j as Map<String, dynamic>)).toList(),
    subtitleTracks: (json['subtitle_tracks'] as List<dynamic>? ?? []).map((j) => SubtitleTrackInfo.fromJson(j as Map<String, dynamic>)).toList(),
  );
}

/// Mirrors `WatchUserData` from src/api/watch.ts.
class WatchUserData {
  const WatchUserData({this.played, this.isInProgress, this.positionSeconds, this.durationSeconds, this.lastFileId});
  final bool? played;
  final bool? isInProgress;
  final double? positionSeconds;
  final double? durationSeconds;
  final int? lastFileId;

  factory WatchUserData.fromJson(Map<String, dynamic> json) => WatchUserData(
    played: json['played'] as bool?,
    isInProgress: json['is_in_progress'] as bool?,
    positionSeconds: (json['position_seconds'] as num?)?.toDouble(),
    durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
    lastFileId: json['last_file_id'] as int?,
  );
}

/// Mirrors `WatchDetail` from src/api/watch.ts.
class WatchDetail {
  const WatchDetail({
    required this.contentId,
    required this.type,
    required this.title,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.year,
    this.versions = const [],
    this.userData,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String contentId;
  final String type;
  final String title;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final int? year;
  final List<FileVersion> versions;
  final WatchUserData? userData;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;

  factory WatchDetail.fromJson(Map<String, dynamic> json) => WatchDetail(
    contentId: json['content_id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    overview: json['overview'] as String?,
    posterUrl: json['poster_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    year: json['year'] as int?,
    versions: (json['versions'] as List<dynamic>? ?? []).map((j) => FileVersion.fromJson(j as Map<String, dynamic>)).toList(),
    userData: json['user_data'] != null ? WatchUserData.fromJson(json['user_data'] as Map<String, dynamic>) : null,
    seriesId: json['series_id'] as String?,
    seasonNumber: json['season_number'] as int?,
    episodeNumber: json['episode_number'] as int?,
  );
}

/// Mirrors `PlayerLaunch` from src/screens/PlayerScreen.tsx, extended with
/// pre-play audio/subtitle choices made on Item Detail (not part of the TS
/// original, which only ever offered mid-playback switching).
class PlayerLaunch {
  const PlayerLaunch({
    required this.fileId,
    this.title,
    this.contentId,
    this.startPositionSeconds,
    this.watch,
    this.initialAudioTrackIndex,
    this.initialSubtitleLanguage,
  });

  final int fileId;
  final String? title;
  final String? contentId;
  final double? startPositionSeconds;
  final WatchDetail? watch;
  /// Index into the selected file's `audioTracks`, chosen ahead of time.
  final int? initialAudioTrackIndex;
  /// Subtitle language to auto-select on start — `''` means explicitly off,
  /// `null` means fall back to the saved preferred-subtitle-language setting.
  final String? initialSubtitleLanguage;
}
