import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors ItemDetailScreen.tsx. Viewport-based lazy-loading/hero-settle
/// timing (IntersectionObserver, `heroSettled`/`heroBackdropReady` gating)
/// isn't ported — Flutter's own lazy list/grid builders and image caching
/// cover the same concern natively, so there's no JS-main-thread decode
/// contention to design around here.
class ItemDetailScreen extends ConsumerStatefulWidget {
  const ItemDetailScreen({super.key, required this.contentId, this.seed, required this.back});

  final String contentId;
  final CatalogItem? seed;
  final Route back;

  @override
  ConsumerState<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<ItemDetailScreen> {
  ItemDetail? _detail;
  List<SeasonSummary> _seasons = [];
  int? _seasonNumber;
  List<EpisodeSummary> _episodes = [];
  bool _episodesLoading = false;
  List<CatalogItem> _similar = [];
  bool _loading = true;
  bool _busyPlay = false;
  bool _busyAction = false;
  String? _error;

  // Optimistic user-state overrides (ItemDetail/CatalogItem are immutable).
  bool? _favoriteOverride;
  bool? _watchlistOverride;
  bool? _playedOverride;

  final _watchCache = <String, WatchDetail>{};

  bool get _isFavorite => _favoriteOverride ?? _detail?.item.userState?.isFavorite ?? false;
  bool get _inWatchlist => _watchlistOverride ?? _detail?.item.userState?.inWatchlist ?? false;
  bool get _played => _playedOverride ?? _detail?.item.userState?.played ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isSeriesType(String? type) => const {'series', 'show', 'tv'}.contains(type?.toLowerCase());

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _seasons = [];
      _episodes = [];
      _seasonNumber = null;
      _similar = [];
      _favoriteOverride = null;
      _watchlistOverride = null;
      _playedOverride = null;
      _watchCache.clear();
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final item = await fetchItemDetail(client, session, widget.contentId);
      if (!mounted) return;
      setState(() {
        _detail = item;
        _loading = false;
      });
      if (_isSeriesType(item.item.type)) {
        _loadSeasons();
      }
      _loadSimilar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiError ? e.message : 'Could not load title';
        _loading = false;
      });
    }
  }

  Future<void> _loadSeasons() async {
    try {
      final seasons = await fetchSeasons(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId);
      if (!mounted || seasons.isEmpty) return;
      setState(() => _seasons = seasons);
      _selectSeason(seasons.first.seasonNumber);
    } catch (_) {
      // Seasons are optional — a movie or a server without the endpoint
      // must not block the rest of the page.
    }
  }

  Future<void> _selectSeason(int seasonNumber) async {
    setState(() {
      _seasonNumber = seasonNumber;
      _episodesLoading = true;
    });
    try {
      final episodes = await fetchEpisodes(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId, seasonNumber);
      if (!mounted) return;
      setState(() => _episodes = episodes);
    } catch (_) {
      // Ignore — episode grid just stays empty for this season.
    } finally {
      if (mounted) setState(() => _episodesLoading = false);
    }
  }

  Future<void> _loadSimilar() async {
    try {
      final result = await fetchSimilarItems(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId);
      if (!mounted) return;
      setState(() => _similar = result.cards);
    } catch (_) {
      // Recommendations are optional.
    }
  }

  Future<WatchDetail> _resolveWatchDetail(String id) async {
    final cached = _watchCache[id];
    if (cached != null) return cached;
    final detail = _detail;
    if (detail != null && detail.item.contentId == id && detail.versions.isNotEmpty) {
      final watch = WatchDetail(
        contentId: detail.item.contentId,
        type: detail.item.type,
        title: detail.item.title,
        overview: detail.item.overview,
        posterUrl: detail.item.posterUrl,
        backdropUrl: detail.item.backdropUrl,
        year: detail.item.year,
        versions: detail.versions
            .map((v) => FileVersion(fileId: v.fileId, resolution: v.resolution, codecVideo: v.codecVideo, codecAudio: v.codecAudio))
            .toList(),
        seriesId: detail.seriesId,
        seasonNumber: detail.item.seasonNumber,
        episodeNumber: detail.item.episodeNumber,
      );
      _watchCache[id] = watch;
      return watch;
    }
    final watch = await fetchWatchDetail(ref.read(apiClientProvider), ref.read(sessionProvider)!, id);
    _watchCache[id] = watch;
    return watch;
  }

  /// Mirrors `resumePositionSeconds` from src/lib/detailMetadata.ts.
  double? _resumePosition(double? position, double? duration) {
    if (position == null || position <= 0) return null;
    if (duration != null && duration > 0 && position / duration >= 0.95) return null;
    return position;
  }

  Future<void> _play(String id, String title, {bool startFromBeginning = false}) async {
    setState(() {
      _busyPlay = true;
      _error = null;
    });
    try {
      final watch = await _resolveWatchDetail(id);
      final fileId = selectPlaybackFileId(watch);
      if (fileId == null) throw StateError('No playable file for this title');
      final startPosition = startFromBeginning ? null : _resumePosition(watch.userData?.positionSeconds, watch.userData?.durationSeconds);
      if (!mounted) return;
      ref.read(routeProvider.notifier).go(
        PlayerRoute(
          launch: PlayerLaunch(fileId: fileId, title: watch.title.isNotEmpty ? watch.title : title, contentId: id, startPositionSeconds: startPosition, watch: watch),
          back: DetailRoute(contentId: widget.contentId, seed: widget.seed, back: widget.back),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Play failed');
    } finally {
      if (mounted) setState(() => _busyPlay = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_detail == null) return;
    final next = !_isFavorite;
    setState(() {
      _favoriteOverride = next;
      _busyAction = true;
    });
    try {
      await setFavorite(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId, next);
    } catch (e) {
      if (mounted) setState(() => _favoriteOverride = !next);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_detail == null) return;
    final next = !_inWatchlist;
    setState(() {
      _watchlistOverride = next;
      _busyAction = true;
    });
    try {
      await setWatchlist(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId, next);
    } catch (e) {
      if (mounted) setState(() => _watchlistOverride = !next);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _toggleWatched() async {
    if (_detail == null) return;
    final next = !_played;
    setState(() {
      _playedOverride = next;
      _busyAction = true;
    });
    try {
      await setWatched(ref.read(apiClientProvider), ref.read(sessionProvider)!, widget.contentId, next);
    } catch (e) {
      if (mounted) setState(() => _playedOverride = !next);
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final detail = _detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(widget.back);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(detail?.item.title ?? widget.seed?.title ?? 'Loading…', style: const TextStyle(fontFamily: 'Fraunces')),
          leading: BackButton(onPressed: () => ref.read(routeProvider.notifier).go(widget.back)),
        ),
        body: _loading && detail == null
          ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
          : detail == null
          ? Center(child: Text(_error ?? 'Not found', style: const TextStyle(color: PrairieColors.danger)))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(_error!, style: const TextStyle(color: PrairieColors.danger))),
                _Hero(
                  detail: detail,
                  serverUrl: session.serverUrl,
                  busyPlay: _busyPlay,
                  busyAction: _busyAction,
                  isFavorite: _isFavorite,
                  inWatchlist: _inWatchlist,
                  played: _played,
                  onPlay: () => _play(widget.contentId, detail.item.title),
                  onStartOver: () => _play(widget.contentId, detail.item.title, startFromBeginning: true),
                  onToggleFavorite: _toggleFavorite,
                  onToggleWatchlist: _toggleWatchlist,
                  onToggleWatched: _toggleWatched,
                ),
                const SizedBox(height: 24),
                if (_isSeriesType(detail.item.type) && _seasons.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final season in _seasons)
                        ChoiceChip(
                          label: Text(season.title ?? 'Season ${season.seasonNumber}'),
                          selected: _seasonNumber == season.seasonNumber,
                          onSelected: (_) => _selectSeason(season.seasonNumber),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_episodesLoading)
                    const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 280, mainAxisExtent: 200, crossAxisSpacing: 14, mainAxisSpacing: 14),
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final episode = _episodes[index];
                        return _EpisodeCard(episode: episode, serverUrl: session.serverUrl, onTap: () => _play(episode.contentId, episode.title));
                      },
                    ),
                ],
                if (detail.cast.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  MediaRow<CastMember>(
                    title: 'Cast',
                    items: detail.cast,
                    itemBuilder: (context, member, index) => SizedBox(
                      width: 120,
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: PrairieColors.bgElevated,
                            backgroundImage: member.photoUrl != null ? NetworkImage(resolveAssetUrl(session.serverUrl, member.photoUrl!)) : null,
                            child: member.photoUrl == null ? const Icon(Icons.person, color: PrairieColors.muted) : null,
                          ),
                          const SizedBox(height: 8),
                          Text(member.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.ink, fontSize: 13)),
                          if (member.character != null)
                            Text(member.character!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_similar.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  MediaRow<CatalogItem>(
                    title: 'More like this',
                    items: _similar,
                    itemBuilder: (context, item, index) => PosterCard(
                      title: item.title,
                      subtitle: item.subtitle,
                      posterUrl: item.posterUrl,
                      serverUrl: session.serverUrl,
                      watched: item.userState?.played ?? false,
                      onTap: () => ref.read(routeProvider.notifier).go(
                        DetailRoute(contentId: item.contentId, seed: item, back: DetailRoute(contentId: widget.contentId, seed: widget.seed, back: widget.back)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }
}

/// Mirrors `.detail-hero`: backdrop art fills the section, and everything —
/// poster thumbnail, title, tagline, meta, overview, and the Play/Start
/// over/favorite/watchlist/watched row — sits stacked on top of it as one
/// piece of content, not as separate blocks below a small banner.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.detail,
    required this.serverUrl,
    required this.busyPlay,
    required this.busyAction,
    required this.isFavorite,
    required this.inWatchlist,
    required this.played,
    required this.onPlay,
    required this.onStartOver,
    required this.onToggleFavorite,
    required this.onToggleWatchlist,
    required this.onToggleWatched,
  });

  final ItemDetail detail;
  final String serverUrl;
  final bool busyPlay;
  final bool busyAction;
  final bool isFavorite;
  final bool inWatchlist;
  final bool played;
  final VoidCallback onPlay;
  final VoidCallback onStartOver;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onToggleWatched;

  @override
  Widget build(BuildContext context) {
    final backdrop = detail.item.backdropUrl;
    final poster = detail.item.posterUrl;
    // Mirrors `.detail-hero { min-height: min(70vh, 640px) }` — TV viewports
    // are essentially always tall enough to hit the 640px cap.
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.7).clamp(0, 640).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: heroHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: const BoxDecoration(color: PrairieColors.bgElevated)),
            ),
            if (backdrop != null)
              Positioned.fill(
                child: Image.network(resolveAssetUrl(serverUrl, backdrop), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            // Mirrors `.detail-hero__shade`: a left-to-right gradient (dark
            // where the copy sits, fading out toward the right so the
            // backdrop art stays visible), not a bottom-up scrim.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF0A0C10).withValues(alpha: 0.92),
                      const Color(0xFF0A0C10).withValues(alpha: 0.55),
                      const Color(0xFF0A0C10).withValues(alpha: 0.25),
                    ],
                    stops: const [0.18, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Mirrors `.detail-hero__content { align-content: end }` —
            // content is anchored to the bottom of the hero, not centered.
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (poster != null && backdrop != null) ...[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 18))],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              resolveAssetUrl(serverUrl, poster),
                              width: 160,
                              height: 240,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(width: 160, height: 240, child: PosterFallback()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (detail.item.logoUrl != null)
                              Image.network(
                                resolveAssetUrl(serverUrl, detail.item.logoUrl!),
                                height: 64,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                errorBuilder: (_, _, _) =>
                                    Text(detail.item.title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.ink)),
                              )
                            else
                              Text(detail.item.title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.ink)),
                            if (detail.tagline != null) ...[
                              const SizedBox(height: 4),
                              Text(detail.tagline!, style: const TextStyle(color: PrairieColors.amber, fontStyle: FontStyle.italic)),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              [
                                if (detail.item.year != null) '${detail.item.year}',
                                if (detail.item.runtime != null) '${detail.item.runtime} min',
                                if (detail.item.ratingImdb != null) '★ ${detail.item.ratingImdb!.toStringAsFixed(1)}',
                                if (detail.item.contentRating != null) detail.item.contentRating!,
                              ].join(' · '),
                              style: const TextStyle(color: PrairieColors.muted),
                            ),
                            if (detail.item.overview != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                detail.item.overview!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PrairieColors.muted, height: 1.4),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  autofocus: true,
                                  onPressed: busyPlay ? null : onPlay,
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(busyPlay ? 'Loading…' : 'Play'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: busyPlay ? null : onStartOver,
                                  icon: const Icon(Icons.replay),
                                  label: const Text('Start over'),
                                ),
                                IconButton(
                                  onPressed: busyAction ? null : onToggleFavorite,
                                  icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: PrairieColors.amber),
                                  tooltip: 'Favorite',
                                ),
                                IconButton(
                                  onPressed: busyAction ? null : onToggleWatchlist,
                                  icon: Icon(inWatchlist ? Icons.bookmark : Icons.bookmark_border, color: PrairieColors.amber),
                                  tooltip: 'Watchlist',
                                ),
                                IconButton(
                                  onPressed: busyAction ? null : onToggleWatched,
                                  icon: Icon(played ? Icons.check_circle : Icons.check_circle_outline, color: PrairieColors.amber),
                                  tooltip: 'Watched',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.episode, required this.serverUrl, required this.onTap});

  final EpisodeSummary episode;
  final String serverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = episode.stillUrl ?? episode.posterUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: still != null
                  ? Image.network(resolveAssetUrl(serverUrl, still), fit: BoxFit.cover, errorBuilder: (_, _, _) => const PosterFallback())
                  : const PosterFallback(),
            ),
          ),
          const SizedBox(height: 6),
          Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.ink, fontSize: 13)),
          Text(
            'Episode ${episode.episodeNumber ?? ''}',
            style: const TextStyle(color: PrairieColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
