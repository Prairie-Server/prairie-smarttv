import '../api/catalog_api.dart';
import '../models/catalog_item.dart';

/// Mirrors `formatRuntimeMinutes` from src/lib/detailMetadata.ts.
String? formatRuntimeMinutes(int? runtimeMinutes) {
  if (runtimeMinutes == null || runtimeMinutes <= 0) return null;
  if (runtimeMinutes < 60) return '${runtimeMinutes}m';
  final h = runtimeMinutes ~/ 60;
  final m = runtimeMinutes % 60;
  return m > 0 ? '${h}h ${m}m' : '${h}h';
}

/// Mirrors `formatRuntimeSeconds`.
String? formatRuntimeSeconds(num? seconds) {
  if (seconds == null || seconds <= 0) return null;
  return formatRuntimeMinutes((seconds / 60).round());
}

/// Mirrors `typeLabel`.
String typeLabel(String? type) {
  if (type == null || type.isEmpty) return 'Title';
  switch (type.toLowerCase()) {
    case 'movie':
      return 'Movie';
    case 'series':
    case 'show':
    case 'tv':
      return 'TV Show';
    case 'episode':
      return 'Episode';
    case 'season':
      return 'Season';
    default:
      return '${type[0].toUpperCase()}${type.substring(1)}';
  }
}

bool isSeriesType(String? type) {
  if (type == null) return false;
  final t = type.toLowerCase();
  return t == 'series' || t == 'show' || t == 'tv';
}

/// Mirrors `resumePositionSeconds`.
double? resumePositionSeconds(double? position, double? duration) {
  if (position == null || position <= 0) return null;
  if (duration != null && duration > 0 && position / duration >= 0.95) return null;
  return position;
}

/// Mirrors `hasResumeProgress`.
bool hasResumeProgress(double? position, double? duration, {bool? isInProgress}) {
  if (isInProgress == true) return true;
  final seconds = resumePositionSeconds(position, duration);
  return seconds != null && seconds > 30;
}

/// Mirrors `formatResumeLabel`.
String formatResumeLabel(num positionSeconds) {
  final total = positionSeconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return 'Resume $h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return 'Resume $m:${s.toString().padLeft(2, '0')}';
}

/// Mirrors `pickNextUpEpisode`.
EpisodeSummary? pickNextUpEpisode(List<EpisodeSummary> episodes) {
  if (episodes.isEmpty) return null;
  for (final ep in episodes) {
    if (ep.userData?.isInProgress == true) return ep;
  }
  for (final ep in episodes) {
    if (!(ep.userData?.played ?? false)) return ep;
  }
  return episodes.first;
}

/// Mirrors `formatAirDate`.
String? formatAirDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final date = DateTime.tryParse(raw);
  if (date == null) return raw.length >= 10 ? raw.substring(0, 10) : raw;
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

/// Mirrors `crewLine`.
String? crewLine(ItemDetail detail) {
  final directors = detail.crew
      .where((c) => RegExp(r'director|creator', caseSensitive: false).hasMatch(c.job))
      .map((c) => c.name)
      .where((n) => n.isNotEmpty)
      .toSet()
      .take(3)
      .toList();
  if (directors.isEmpty) return null;
  final label = isSeriesType(detail.item.type) ? 'Created by' : 'Directed by';
  return '$label ${directors.join(', ')}';
}

/// Mirrors `starringText`.
String? starringText(ItemDetail detail) {
  final names = detail.cast.take(3).map((c) => c.name).where((n) => n.isNotEmpty).toList();
  if (names.isEmpty) return null;
  return 'Starring ${names.join(', ')}';
}

/// Mirrors `isContinueStyleSection` / `usesLandscapeCards` from browseCards.ts.
bool isContinueStyleSection(String? sectionType) {
  if (sectionType == null) return false;
  final t = sectionType.toLowerCase();
  return t == 'continue_watching' || t == 'next_up' || t == 'on_deck';
}

bool usesLandscapeCards(String? sectionType, List<CatalogItem> items) {
  if (!isContinueStyleSection(sectionType)) return false;
  return items.any((item) => item.type == 'episode');
}

/// Preferred file among [versions] using last-played preference.
ItemVersion? preferredVersion(ItemDetail detail) {
  if (detail.versions.isEmpty) return null;
  final lastId = detail.userData?.lastFileId;
  if (lastId != null) {
    for (final v in detail.versions) {
      if (v.fileId == lastId) return v;
    }
  }
  return detail.versions.first;
}

String? resolutionLabel(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final lower = raw.toLowerCase();
  if (lower.contains('2160') || lower.contains('4k')) return '4K';
  if (lower.contains('1080') || lower.contains('720')) return 'HD';
  if (lower.contains('480')) return 'SD';
  return null;
}

List<String> movieFactTokens(ItemDetail detail) {
  final tokens = <String>[];
  if (detail.item.year != null && detail.item.year! > 0) tokens.add('${detail.item.year}');
  final runtime = formatRuntimeMinutes(detail.item.runtime);
  if (runtime != null) tokens.add(runtime);
  if (detail.item.ratingImdb != null) tokens.add(detail.item.ratingImdb!.toStringAsFixed(1));
  final version = preferredVersion(detail);
  if (version != null) {
    final res = resolutionLabel(version.resolution);
    if (res != null) tokens.add(res);
    if (version.hdr == true) tokens.add('HDR');
  }
  return tokens;
}

List<String> seriesFactTokens(ItemDetail detail, {int? seasonCount}) {
  final tokens = <String>[];
  if (detail.item.year != null && detail.item.year! > 0) tokens.add('${detail.item.year}');
  final seasons = seasonCount ?? detail.seasonCount;
  if (seasons != null && seasons > 0) {
    tokens.add('$seasons Season${seasons == 1 ? '' : 's'}');
  }
  if (detail.episodeCount != null && detail.episodeCount! > 0) {
    tokens.add('${detail.episodeCount} Episode${detail.episodeCount == 1 ? '' : 's'}');
  }
  if (detail.item.ratingImdb != null) tokens.add(detail.item.ratingImdb!.toStringAsFixed(1));
  return tokens;
}
