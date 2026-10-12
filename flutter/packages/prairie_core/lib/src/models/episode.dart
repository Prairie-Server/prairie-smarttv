/// One playable episode of a series, as the player navigates between them.
class EpisodeRef {
  const EpisodeRef({
    required this.contentId,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final String contentId;
  final String title;
  final int seasonNumber;
  final int episodeNumber;

  /// `S1 · E4`, for the up-next card.
  String get code => 'S$seasonNumber · E$episodeNumber';
}

/// The playing episode's neighborhood: playable episodes in airing order,
/// built by `loadSeriesContext`. Only seasons adjacent to the one that was
/// loaded around are present, which is all prev/next needs.
class SeriesContext {
  const SeriesContext({required this.seriesId, this.seriesTitle, required this.episodes});

  final String seriesId;
  final String? seriesTitle;
  final List<EpisodeRef> episodes;

  EpisodeRef? previousOf(String contentId) => _neighbor(contentId, -1);
  EpisodeRef? nextOf(String contentId) => _neighbor(contentId, 1);

  EpisodeRef? _neighbor(String contentId, int step) {
    final index = episodes.indexWhere((e) => e.contentId == contentId);
    if (index < 0) return null;
    final target = index + step;
    return target >= 0 && target < episodes.length ? episodes[target] : null;
  }
}
