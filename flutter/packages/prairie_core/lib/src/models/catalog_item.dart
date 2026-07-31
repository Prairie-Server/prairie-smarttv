/// Mirrors `MediaItemUserState` from src/api/catalog.ts.
class MediaItemUserState {
  const MediaItemUserState({this.played, this.isFavorite, this.inWatchlist});
  final bool? played;
  final bool? isFavorite;
  final bool? inWatchlist;

  factory MediaItemUserState.fromJson(Map<String, dynamic> json) => MediaItemUserState(
    played: json['played'] as bool?,
    isFavorite: json['is_favorite'] as bool?,
    inWatchlist: json['in_watchlist'] as bool?,
  );
}

/// Mirrors `CatalogItem` from src/api/catalog.ts.
class CatalogItem {
  const CatalogItem({
    required this.contentId,
    required this.type,
    required this.title,
    this.year,
    this.runtime,
    this.genres,
    this.contentRating,
    this.ratingImdb,
    this.overview,
    this.posterUrl,
    this.posterAvifUrl,
    this.backdropUrl,
    this.backdropAvifUrl,
    this.logoUrl,
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.positionSeconds,
    this.durationSeconds,
    this.userState,
  });

  final String contentId;
  final String type;
  final String title;
  final int? year;
  final int? runtime;
  final List<String>? genres;
  final String? contentRating;
  final double? ratingImdb;
  final String? overview;
  final String? posterUrl;
  final String? posterAvifUrl;
  final String? backdropUrl;
  final String? backdropAvifUrl;
  final String? logoUrl;
  final String? seriesId;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final double? positionSeconds;
  final double? durationSeconds;
  final MediaItemUserState? userState;

  /// Mirrors `catalogItemSubtitle` from src/lib/browseCards.ts.
  String? get subtitle {
    if (seriesTitle != null && seasonNumber != null && episodeNumber != null) {
      return '$seriesTitle · S${seasonNumber}E$episodeNumber';
    }
    final bits = <String>[];
    if (year != null) bits.add('$year');
    if (ratingImdb != null) bits.add('★ ${ratingImdb!.toStringAsFixed(1)}');
    if (bits.isNotEmpty) return bits.join(' · ');
    if (type.isNotEmpty) return type;
    return null;
  }

  /// Mirrors `catalogItemProgress` from src/lib/browseCards.ts: fraction
  /// watched, or null when there's no meaningful in-progress position.
  double? get progress {
    final pos = positionSeconds;
    final dur = durationSeconds;
    if (pos == null || dur == null || dur <= 0) return null;
    return (pos / dur).clamp(0.0, 1.0);
  }
}
