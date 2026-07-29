import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/detail_metadata.dart';

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
  int? _selectedFileId;

  // Optimistic user-state overrides (ItemDetail/CatalogItem are immutable).
  bool? _favoriteOverride;
  bool? _watchlistOverride;
  bool? _playedOverride;

  final _watchCache = <String, WatchDetail>{};
  final _scrollController = ScrollController();
  final _playFocus = FocusNode(debugLabel: 'detail-play');
  final _backFocus = FocusNode(debugLabel: 'detail-back');
  /// Once the viewer moves focus/scroll themselves, stop re-pinning to Play.
  bool _userMovedFocus = false;
  bool _pinScheduled = false;
  bool _pinning = false;
  /// Lower rails stay unfocusable until the hero actions have been focused once,
  /// so async "More like this" mounts can't steal the initial focus.
  bool _heroPinned = false;

  bool get _isFavorite => _favoriteOverride ?? _detail?.item.userState?.isFavorite ?? false;
  bool get _inWatchlist => _watchlistOverride ?? _detail?.item.userState?.inWatchlist ?? false;
  bool get _played => _playedOverride ?? _detail?.item.userState?.played ?? false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusManagerChange);
    _load();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusManagerChange);
    _scrollController.dispose();
    _playFocus.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  void _onFocusManagerChange() {
    if (_pinning || !_heroPinned || _userMovedFocus) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return;
    if (primary == _playFocus || primary == _backFocus) return;
    // Focus landed below the hero (seasons, episodes, More like this, …).
    _userMovedFocus = true;
  }

  /// Keep the hero actions focused at the top. Async seasons/similar mounts
  /// otherwise steal focus onto "More like this" posters and scroll them into
  /// view — after which D-pad up can't escape the horizontal rail.
  void _pinToHeroActions({required bool playEnabled}) {
    if (_userMovedFocus || !mounted) return;
    if (_pinScheduled) return;
    _pinScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinScheduled = false;
      if (!mounted || _userMovedFocus) return;
      _pinning = true;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _playFocus.skipTraversal = !playEnabled;
      final target = playEnabled ? _playFocus : _backFocus;
      target.requestFocus();
      _pinning = false;
      if (!_heroPinned && mounted) {
        setState(() => _heroPinned = true);
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _seasons = [];
      _episodes = [];
      _seasonNumber = null;
      _similar = [];
      _selectedFileId = null;
      _favoriteOverride = null;
      _watchlistOverride = null;
      _playedOverride = null;
      _watchCache.clear();
      _userMovedFocus = false;
      _heroPinned = false;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final item = await fetchItemDetail(client, session, widget.contentId);
      if (!mounted) return;
      setState(() {
        _detail = item;
        _selectedFileId = preferredVersion(item)?.fileId;
        _loading = false;
      });
      _pinToHeroActions(playEnabled: !isSeriesType(item.item.type));
      if (isSeriesType(item.item.type)) {
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
      _pinToHeroActions(playEnabled: false);
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
      _pinToHeroActions(playEnabled: pickNextUpEpisode(episodes) != null);
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
      final detail = _detail;
      final playEnabled = detail != null &&
          (!isSeriesType(detail.item.type) || pickNextUpEpisode(_episodes) != null);
      _pinToHeroActions(playEnabled: playEnabled);
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
        userData: detail.userData,
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

  Future<void> _play(String id, String title, {bool startFromBeginning = false, int? preferredFileId}) async {
    setState(() {
      _busyPlay = true;
      _error = null;
    });
    try {
      final watch = await _resolveWatchDetail(id);
      final fileId = selectPlaybackFileId(watch, preferredFileId: preferredFileId ?? (id == widget.contentId ? _selectedFileId : null));
      if (fileId == null) throw StateError('No playable file for this title');
      final startPosition = startFromBeginning
          ? null
          : resumePositionSeconds(watch.userData?.positionSeconds, watch.userData?.durationSeconds);
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

  String _playLabel({required bool isSeries, EpisodeSummary? nextUp}) {
    if (_busyPlay) return 'Starting…';
    final detail = _detail;
    if (detail == null) return 'Play';
    if (!isSeries) {
      final movieResume = hasResumeProgress(
        detail.userData?.positionSeconds,
        detail.userData?.durationSeconds,
        isInProgress: detail.userData?.isInProgress,
      );
      final seconds = resumePositionSeconds(detail.userData?.positionSeconds, detail.userData?.durationSeconds);
      if (movieResume && seconds != null) return formatResumeLabel(seconds);
      return 'Play';
    }
    if (nextUp == null) return 'Play';
    final code = nextUp.seasonNumber != null && nextUp.episodeNumber != null
        ? 'S${nextUp.seasonNumber} · E${nextUp.episodeNumber}'
        : null;
    final episodeResume = hasResumeProgress(
      nextUp.userData?.positionSeconds,
      nextUp.userData?.durationSeconds,
      isInProgress: nextUp.userData?.isInProgress,
    );
    if (episodeResume) return code != null ? 'Resume $code' : 'Resume';
    return code != null ? 'Play $code' : 'Play';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final detail = _detail;
    final isSeries = detail != null && isSeriesType(detail.item.type);
    final nextUp = isSeries ? pickNextUpEpisode(_episodes) : null;
    final movieResume = detail != null &&
        !isSeries &&
        hasResumeProgress(
          detail.userData?.positionSeconds,
          detail.userData?.durationSeconds,
          isInProgress: detail.userData?.isInProgress,
        );
    final episodeResume = nextUp != null &&
        hasResumeProgress(
          nextUp.userData?.positionSeconds,
          nextUp.userData?.durationSeconds,
          isInProgress: nextUp.userData?.isInProgress,
        );
    final showStartOver = movieResume || (isSeries && episodeResume);
    final playLabel = _playLabel(isSeries: isSeries, nextUp: nextUp);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(routeProvider.notifier).go(widget.back);
      },
      child: Scaffold(
        body: _loading && detail == null
          ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
          : detail == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error ?? 'Not found', style: const TextStyle(color: PrairieColors.danger)),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => ref.read(routeProvider.notifier).go(widget.back),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                ],
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  _userMovedFocus = true;
                }
                return false;
              },
              child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.zero,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
                  ),
                _Hero(
                  detail: detail,
                  serverUrl: session.serverUrl,
                  busyPlay: _busyPlay,
                  busyAction: _busyAction,
                  isFavorite: _isFavorite,
                  inWatchlist: _inWatchlist,
                  played: _played,
                  playLabel: playLabel,
                  showStartOver: showStartOver,
                  playEnabled: !isSeries || nextUp != null,
                  seasonCount: _seasons.length,
                  playFocusNode: _playFocus,
                  backFocusNode: _backFocus,
                  onBack: () => ref.read(routeProvider.notifier).go(widget.back),
                  onPlay: () {
                    if (isSeries) {
                      if (nextUp == null) return;
                      _play(nextUp.contentId, nextUp.title);
                    } else {
                      _play(widget.contentId, detail.item.title);
                    }
                  },
                  onStartOver: () {
                    if (isSeries && nextUp != null) {
                      _play(nextUp.contentId, nextUp.title, startFromBeginning: true);
                    } else {
                      _play(widget.contentId, detail.item.title, startFromBeginning: true);
                    }
                  },
                  onToggleFavorite: _toggleFavorite,
                  onToggleWatchlist: _toggleWatchlist,
                  onToggleWatched: _toggleWatched,
                ),
                ExcludeFocus(
                  excluding: !_heroPinned,
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                if (!isSeries && detail.versions.length > 1) ...[
                  const SizedBox(height: 24),
                  const Text('Version', style: TextStyle(fontFamily: 'Fraunces', fontSize: 20, color: PrairieColors.ink)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final version in detail.versions)
                        ChoiceChip(
                          label: Text(_versionLabel(version)),
                          selected: _selectedFileId == version.fileId,
                          onSelected: (_) => setState(() => _selectedFileId = version.fileId),
                        ),
                    ],
                  ),
                ],
                if (isSeries && _seasons.isNotEmpty) ...[
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
                if (detail.extras.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Text('Bonus Content', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
                  const SizedBox(height: 4),
                  const Text('Extras', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      for (final extra in detail.extras)
                        OutlinedButton.icon(
                          onPressed: _busyPlay ? null : () => _play(extra.contentId, extra.title ?? 'Extra'),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(extra.title?.isNotEmpty == true ? extra.title! : extra.kind),
                        ),
                    ],
                  ),
                ],
                if (_hasDetailsSection(detail)) ...[
                  const SizedBox(height: 32),
                  const Text('Details', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
                  const SizedBox(height: 4),
                  const Text('Info', style: TextStyle(color: PrairieColors.muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  _DetailsTable(detail: detail, isSeries: isSeries),
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
                ),
              ],
            ),
            ),
      ),
    );
  }

  bool _hasDetailsSection(ItemDetail detail) {
    return (detail.item.genres?.isNotEmpty ?? false) ||
        detail.studios.isNotEmpty ||
        detail.networks.isNotEmpty ||
        detail.releaseDate != null ||
        detail.firstAirDate != null ||
        detail.showStatus != null;
  }

  String _versionLabel(ItemVersion version) {
    final bits = <String>[];
    if (version.resolution != null && version.resolution!.isNotEmpty) bits.add(version.resolution!);
    if (version.codecVideo != null && version.codecVideo!.isNotEmpty) bits.add(version.codecVideo!);
    if (version.hdr == true) bits.add('HDR');
    if (version.container != null && version.container!.isNotEmpty) bits.add(version.container!);
    return bits.isEmpty ? 'File ${version.fileId}' : bits.join(' · ');
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
    required this.playLabel,
    required this.showStartOver,
    required this.playEnabled,
    required this.seasonCount,
    required this.playFocusNode,
    required this.backFocusNode,
    required this.onBack,
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
  final String playLabel;
  final bool showStartOver;
  final bool playEnabled;
  final int seasonCount;
  final FocusNode playFocusNode;
  final FocusNode backFocusNode;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onStartOver;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onToggleWatched;

  @override
  Widget build(BuildContext context) {
    final backdrop = detail.item.backdropUrl;
    final poster = detail.item.posterUrl;
    final isSeries = isSeriesType(detail.item.type);
    final facts = isSeries ? seriesFactTokens(detail, seasonCount: seasonCount) : movieFactTokens(detail);
    final directed = crewLine(detail);
    final starring = starringText(detail);
    final sources = [
      typeLabel(detail.item.type),
      ...?detail.item.genres?.take(2),
    ];
    // Size the hero to its content so ListView doesn't scroll through a tall
    // empty region past the Play row. Backdrop fills via Positioned.
    return Stack(
      children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: PrairieColors.bgElevated))),
        if (backdrop != null)
          Positioned.fill(
            child: Image.network(resolveAssetUrl(serverUrl, backdrop), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
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
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  focusNode: backFocusNode,
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: PrairieColors.ink,
                    backgroundColor: const Color(0x590A0C10),
                    padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1024),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
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
                            Text(
                              sources.join(' · '),
                              style: const TextStyle(color: PrairieColors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
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
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (detail.item.contentRating != null)
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: PrairieColors.ink.withValues(alpha: 0.35)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Text(detail.item.contentRating!, style: const TextStyle(color: PrairieColors.ink, fontSize: 12)),
                                    ),
                                  ),
                                Text(facts.join(' · '), style: const TextStyle(color: PrairieColors.muted)),
                              ],
                            ),
                            if (detail.ratingRtCritic != null || detail.ratingRtAudience != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                [
                                  if (detail.ratingRtCritic != null) 'Critics ${detail.ratingRtCritic}%',
                                  if (detail.ratingRtAudience != null) 'Audience ${detail.ratingRtAudience}%',
                                ].join(' · '),
                                style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                              ),
                            ],
                            if (detail.item.overview != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                detail.item.overview!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PrairieColors.muted, height: 1.4),
                              ),
                            ],
                            if (directed != null) ...[
                              const SizedBox(height: 8),
                              Text(directed, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
                            ],
                            if (starring != null) ...[
                              const SizedBox(height: 4),
                              Text(starring, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  focusNode: playFocusNode,
                                  onPressed: (busyPlay || !playEnabled) ? null : onPlay,
                                  icon: const Icon(Icons.play_arrow),
                                  label: Text(playLabel),
                                ),
                                if (showStartOver)
                                  OutlinedButton.icon(
                                    onPressed: busyPlay ? null : onStartOver,
                                    icon: const Icon(Icons.replay),
                                    label: const Text('Start Over'),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailsTable extends StatelessWidget {
  const _DetailsTable({required this.detail, required this.isSeries});

  final ItemDetail detail;
  final bool isSeries;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[];
    if (detail.item.genres?.isNotEmpty ?? false) {
      rows.add(('Genres', detail.item.genres!.join(', ')));
    }
    if (detail.studios.isNotEmpty) rows.add(('Studios', detail.studios.join(', ')));
    if (detail.networks.isNotEmpty) rows.add(('Networks', detail.networks.join(', ')));
    final aired = formatAirDate(detail.releaseDate ?? detail.firstAirDate);
    if (aired != null) rows.add((isSeries ? 'First Aired' : 'Released', aired));
    if (detail.showStatus != null && detail.showStatus!.isNotEmpty) {
      rows.add(('Status', detail.showStatus!));
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 120, child: Text(row.$1, style: const TextStyle(color: PrairieColors.muted, fontSize: 13))),
                Expanded(child: Text(row.$2, style: const TextStyle(color: PrairieColors.ink, fontSize: 14))),
              ],
            ),
          ),
      ],
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
