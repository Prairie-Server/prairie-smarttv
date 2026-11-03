import 'package:prairie_core/src/api/catalog_api.dart';

/// One card in a title page's Trailers & Extras rail: a local extra that
/// plays in Prairie, or a provider video that opens in YouTube. Mirrors
/// Android's and Apple's `TrailerRailEntry`.
sealed class TrailerRailEntry {
  const TrailerRailEntry();

  /// Namespaced, so a local extra whose id matches a YouTube key can't shadow
  /// it.
  String get key;
  String get title;
  String get kind;

  /// The card image: the extra's still, or YouTube's for a remote video.
  String? get thumbnailUrl;

  /// Placeholder shown while a local extra's still loads (or when it has
  /// none).
  String? get thumbhash;
}

class LocalTrailerEntry extends TrailerRailEntry {
  const LocalTrailerEntry(this.extra);

  final ItemExtra extra;

  @override
  String get key => 'local:${extra.contentId}';

  @override
  String get title => _nonBlank(extra.title) ?? extraKindLabel(extra.kind);

  @override
  String get kind => extra.kind;

  @override
  String? get thumbnailUrl => extra.stillUrl;

  @override
  String? get thumbhash => extra.stillThumbhash;
}

class YouTubeTrailerEntry extends TrailerRailEntry {
  const YouTubeTrailerEntry(this.video);

  final ItemVideo video;

  @override
  String get key => 'remote:${video.site}:${video.siteKey}';

  @override
  String get title => _nonBlank(video.name) ?? extraKindLabel(video.kind);

  @override
  String get kind => video.kind;

  @override
  String? get thumbnailUrl => youTubeThumbnailUrl(video.siteKey);

  @override
  String? get thumbhash => null;
}

String? _nonBlank(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// The rail for [detail]: local extras first, in server order, because they
/// play here; then YouTube videos in server order, which hand off to the
/// TV's YouTube app (Android #640, Apple #845). Other sites are dropped:
/// nothing on the TV can open them.
List<TrailerRailEntry> trailerRailEntries(ItemDetail detail) {
  final seen = <String>{};
  return [
    for (final extra in detail.extras) LocalTrailerEntry(extra),
    for (final video in detail.videos)
      if (video.site.toLowerCase() == 'youtube' && video.siteKey.trim().isNotEmpty) YouTubeTrailerEntry(video),
  ].where((entry) => seen.add(entry.key)).toList();
}

/// YouTube's still for a video; `hqdefault` exists for every upload.
String youTubeThumbnailUrl(String siteKey) => 'https://i.ytimg.com/vi/${Uri.encodeComponent(siteKey)}/hqdefault.jpg';

/// The watch-page link the TV's YouTube app opens to a specific video
/// (Android #600).
String youTubeWatchUrl(String siteKey) => 'https://www.youtube.com/watch?v=${Uri.encodeQueryComponent(siteKey)}';

/// The line under a card's title: `YouTube` for a remote video, the runtime
/// for a local extra (`m:ss` or `h:mm:ss`), or null when unknown.
String? trailerRailSecondaryLine(TrailerRailEntry entry) {
  return switch (entry) {
    YouTubeTrailerEntry() => 'YouTube',
    LocalTrailerEntry(:final extra) => _clock(extra.durationSeconds),
  };
}

String? _clock(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds <= 0) return null;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '$minutes:${two(seconds)}';
}

/// A readable label for an extra's or video's `kind`.
String extraKindLabel(String kind) {
  switch (kind.toLowerCase()) {
    case 'trailer':
      return 'Trailer';
    case 'teaser':
      return 'Teaser';
    case 'featurette':
      return 'Featurette';
    case 'behind_the_scenes' || 'behind-the-scenes':
      return 'Behind the Scenes';
    case 'deleted_scene' || 'deleted-scene':
      return 'Deleted Scene';
    case 'interview':
      return 'Interview';
  }
  final words = kind
      .replaceAll(RegExp(r'[_-]'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1));
  final label = words.join(' ');
  return label.isEmpty ? 'Extra' : label;
}
