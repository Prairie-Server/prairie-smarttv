import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/detail_metadata.dart';
import 'package:prairie_core/src/widgets/home_hero.dart';
import 'package:prairie_core/src/widgets/landscape_card.dart';

/// Mirrors HomeBrowseScreen.tsx: featured hero carousel, landscape continue-
/// watching rails, poster rails, and Live TV On now.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.restoreContentId});

  /// Content id to refocus after returning from item details.
  final String? restoreContentId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<HomeSection>> _sections;
  int _heroIndex = 0;
  final _heroFocus = FocusNode(debugLabel: 'home-hero-play');
  final _firstItemFocus = FocusNode(debugLabel: 'home-first-item');
  final _restoreFocus = FocusNode(debugLabel: 'home-restore-item');
  /// `autofocus:true` races the async section load — by the time the first
  /// row's first card mounts, initial D-pad presses may already have landed
  /// on the top nav. Explicitly requesting focus once, like ItemDetail's
  /// hero pin, closes that race.
  bool _initialFocusApplied = false;
  /// Flutter's default focus-follows-scroll (`RenderObject.showOnScreen`)
  /// only scrolls the minimum distance to bring the newly-focused card
  /// within the viewport — after navigating down several rows and back up
  /// with the D-pad, that minimal-scroll behavior can leave the ListView a
  /// few pixels short of offset 0, so the first row renders partly behind
  /// ShellNav's header even though it's the topmost content. Forcing a
  /// hard scroll-to-0 whenever the first row gains focus (below) fixes it.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider)!;
    _sections = fetchHomeSections(ref.read(apiClientProvider), session);
  }

  @override
  void dispose() {
    _heroFocus.dispose();
    _firstItemFocus.dispose();
    _restoreFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFirstRowFocusChange(bool hasFocus) {
    if (!hasFocus || !_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  /// Explicit D-pad-Down target from [ShellNav] — the topmost currently
  /// mounted body focus target, in the same preference order the page
  /// itself would autofocus in. `.context` on a [FocusNode] is non-null
  /// only while its widget is actually in the tree, which is what makes
  /// this reliable across the hero/no-hero and restoring/fresh-load builds.
  FocusNode? _resolveEscapeDownFocus() {
    if (_heroFocus.context != null) return _heroFocus;
    if (_restoreFocus.context != null) return _restoreFocus;
    if (_firstItemFocus.context != null) return _firstItemFocus;
    return null;
  }

  void _applyInitialFocus(FocusNode node) {
    if (_initialFocusApplied) return;
    _initialFocusApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      final ctx = node.context;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openItem(CatalogItem item) {
    ref.read(routeProvider.notifier).go(
      DetailRoute(
        contentId: item.contentId,
        seed: item,
        back: HomeRoute(restoreContentId: item.contentId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final onNow = ref.watch(onNowLiveTvProvider).valueOrNull ?? const <OnNowEntry>[];
    return ShellScaffold(
      active: ShellTab.home,
      escapeDownFocus: _resolveEscapeDownFocus,
      body: FutureBuilder<List<HomeSection>>(
        future: _sections,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: PrairieLoadingIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}', style: const TextStyle(color: PrairieColors.danger)));
          }
          final sections = snapshot.data ?? [];
          HomeSection? featured;
          for (final s in sections) {
            if (s.featured == true && s.items.isNotEmpty) {
              featured = s;
              break;
            }
          }
          // Skip empty catalog rows so "first row" is always a focusable rail.
          final rows = sections.where((s) => s.featured != true && s.items.isNotEmpty).toList();
          if (sections.isEmpty && onNow.isEmpty) {
            return const Center(child: Text('Nothing here yet', style: TextStyle(color: PrairieColors.muted)));
          }

          // Prefer restoring focus to the just-viewed item when returning from
          // details; otherwise land on the first card of the first catalog row
          // (not the featured hero "More Info" button).
          final restoreId = widget.restoreContentId;
          int? restoreSectionIndex;
          int? restoreItemIndex;
          var restoreHero = false;
          if (restoreId != null) {
            for (var s = 0; s < rows.length; s++) {
              final i = rows[s].items.indexWhere((item) => item.contentId == restoreId);
              if (i >= 0) {
                restoreSectionIndex = s;
                restoreItemIndex = i;
                break;
              }
            }
            if (restoreSectionIndex == null && featured != null) {
              restoreHero = featured.items.any((item) => item.contentId == restoreId);
            }
          }
          final restoring = restoreSectionIndex != null && restoreItemIndex != null;
          final firstRowAutofocus = !restoring && !restoreHero && rows.isNotEmpty;
          final firstOnNowAutofocus = !restoring && !restoreHero && rows.isEmpty && onNow.isNotEmpty;
          final heroAutofocus = restoreHero || (!restoring && !firstRowAutofocus && !firstOnNowAutofocus && featured != null);

          if (restoring) {
            _applyInitialFocus(_restoreFocus);
          } else if (firstRowAutofocus || firstOnNowAutofocus) {
            _applyInitialFocus(_firstItemFocus);
          } else if (heroAutofocus) {
            _applyInitialFocus(_heroFocus);
          }

          return ListView(
            controller: _scrollController,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            children: [
              if (featured != null)
                HomeHero(
                  items: featured.items,
                  serverUrl: session.serverUrl,
                  index: _heroIndex,
                  onIndexChange: (i) => setState(() => _heroIndex = i),
                  onOpenItem: _openItem,
                  autofocusPlay: heroAutofocus,
                  playFocusNode: _heroFocus,
                )
              else
                // No featured hero: the first row (often Continue Watching)
                // would otherwise sit right under ShellNav's header with only
                // the rows Column's 24px top padding — not enough clearance
                // once the focused card's box-shadow blur (28px radius) and
                // 1.03x focus scale are accounted for, so it read as clipped
                // behind the header.
                const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Catalog rows first; On now sits further down intentionally
                    // (differs from the old TS home order).
                    for (var s = 0; s < rows.length; s++)
                      _buildSectionRow(
                        session: session,
                        section: rows[s],
                        sectionIndex: s,
                        autofocusFirst: firstRowAutofocus && s == 0,
                        restoreItemIndex: restoring && restoreSectionIndex == s ? restoreItemIndex : null,
                      ),
                    if (onNow.isNotEmpty)
                      MediaRow<OnNowEntry>(
                        title: 'On now',
                        items: onNow,
                        itemBuilder: (context, entry, index) => _OnNowCard(
                          entry: entry,
                          serverUrl: session.serverUrl,
                          autofocus: firstOnNowAutofocus && index == 0,
                          focusNode: firstOnNowAutofocus && index == 0 ? _firstItemFocus : null,
                          onTap: () => ref
                              .read(routeProvider.notifier)
                              .go(LiveTvPlayerRoute(channel: entry.channel, back: const HomeRoute())),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionRow({
    required PrairieSession session,
    required HomeSection section,
    required int sectionIndex,
    required bool autofocusFirst,
    int? restoreItemIndex,
  }) {
    final row = _buildSectionRowContent(
      session: session,
      section: section,
      sectionIndex: sectionIndex,
      autofocusFirst: autofocusFirst,
      restoreItemIndex: restoreItemIndex,
    );
    if (sectionIndex != 0) return row;
    // Only the first row needs the forced scroll-to-top — see
    // [_onFirstRowFocusChange].
    return Focus(canRequestFocus: false, skipTraversal: true, onFocusChange: _onFirstRowFocusChange, child: row);
  }

  Widget _buildSectionRowContent({
    required PrairieSession session,
    required HomeSection section,
    required int sectionIndex,
    required bool autofocusFirst,
    int? restoreItemIndex,
  }) {
    final landscape = usesLandscapeCards(section.sectionType, section.items);
    if (landscape) {
      return MediaRow<CatalogItem>(
        title: section.title,
        items: section.items,
        variant: MediaRowVariant.landscape,
        itemBuilder: (context, item, index) {
          final remaining = (item.durationSeconds != null && item.positionSeconds != null)
              ? formatRuntimeSeconds(item.durationSeconds! - item.positionSeconds!)
              : null;
          final subtitle = item.seriesTitle != null
              ? '${item.seriesTitle}${item.seasonNumber != null && item.episodeNumber != null ? ' · S${item.seasonNumber}E${item.episodeNumber}' : ''}'
              : item.subtitle;
          final isRestore = restoreItemIndex == index;
          // Row 0's card 0 always wears [_firstItemFocus] — not just when
          // [autofocusFirst] requests the initial grab — so it's a stable,
          // always-attached target for [_onEscapeDownFromNav] regardless of
          // whether this particular Home build happens to autofocus it.
          final isFirstCard = sectionIndex == 0 && index == 0;
          return LandscapeCard(
            title: item.title,
            subtitle: subtitle,
            meta: remaining != null ? '$remaining left' : null,
            imageUrl: item.backdropUrl ?? item.posterUrl,
            serverUrl: session.serverUrl,
            progress: item.progress,
            watched: item.userState?.played ?? false,
            autofocus: (autofocusFirst && isFirstCard) || isRestore,
            focusNode: isRestore ? _restoreFocus : (isFirstCard ? _firstItemFocus : null),
            onTap: () => _openItem(item),
          );
        },
      );
    }
    return MediaRow<CatalogItem>(
      title: section.title,
      items: section.items,
      itemBuilder: (context, item, index) {
        final isRestore = restoreItemIndex == index;
        final isFirstCard = sectionIndex == 0 && index == 0;
        return PosterCard(
          title: item.title,
          subtitle: item.subtitle,
          posterUrl: item.posterUrl,
          serverUrl: session.serverUrl,
          watched: item.userState?.played ?? false,
          favorite: item.userState?.isFavorite ?? false,
          progress: item.progress,
          autofocus: (autofocusFirst && isFirstCard) || isRestore,
          focusNode: isRestore ? _restoreFocus : (isFirstCard ? _firstItemFocus : null),
          onTap: () => _openItem(item),
        );
      },
    );
  }
}

class _OnNowCard extends StatefulWidget {
  const _OnNowCard({
    required this.entry,
    required this.serverUrl,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final OnNowEntry entry;
  final String serverUrl;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_OnNowCard> createState() => _OnNowCardState();
}

class _OnNowCardState extends State<_OnNowCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final serverUrl = widget.serverUrl;
    final program = entry.program;
    // On Now shows the program's content art (a poster/still) — the channel
    // logo belongs on the Channels/Guide tabs, not here.
    final posterUrl = program?.imageUrl;
    return InkWell(
      onTap: widget.onTap,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      borderRadius: BorderRadius.circular(14),
      onFocusChange: (value) => setState(() => _focused = value),
      // The theme's default focusColor (a light amber overlay) would
      // otherwise paint on top of the border/glow below.
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _focused ? PrairieColors.ring : Colors.transparent, width: 3),
          boxShadow: _focused ? prairieFocusRing(width: 2) : null,
        ),
        child: SizedBox(
        width: 200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(decoration: BoxDecoration(color: PrairieColors.bgElevated)),
                    if (posterUrl != null)
                      Image.network(
                        resolveAssetUrl(serverUrl, posterUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _channelInitial(entry.channel),
                      )
                    else
                      _channelInitial(entry.channel),
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: PrairieColors.danger, borderRadius: BorderRadius.all(Radius.circular(4))),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(channelDisplayLabel(entry.channel), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
            Text(program?.title ?? 'On air', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.ink, fontSize: 14)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _channelInitial(LiveTvChannel channel) {
    final label = channelDisplayLabel(channel);
    return Center(
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: const TextStyle(fontFamily: 'Fraunces', fontSize: 32, color: PrairieColors.amber),
      ),
    );
  }
}
