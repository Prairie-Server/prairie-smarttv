import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/detail_metadata.dart';
import 'package:prairie_core/src/widgets/home_hero.dart';
import 'package:prairie_core/src/widgets/landscape_card.dart';

/// Mirrors HomeBrowseScreen.tsx: featured hero carousel, landscape continue-
/// watching rails, poster rails, and Live TV On now.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<HomeSection>> _sections;
  int _heroIndex = 0;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider)!;
    _sections = fetchHomeSections(ref.read(apiClientProvider), session);
  }

  void _openItem(CatalogItem item) {
    ref.read(routeProvider.notifier).go(DetailRoute(contentId: item.contentId, seed: item, back: const HomeRoute()));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final onNow = ref.watch(onNowLiveTvProvider).valueOrNull ?? const <OnNowEntry>[];
    return ShellScaffold(
      active: ShellTab.home,
      body: FutureBuilder<List<HomeSection>>(
        future: _sections,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: PrairieColors.amber));
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
          final rows = sections.where((s) => s.featured != true).toList();
          if (sections.isEmpty && onNow.isEmpty) {
            return const Center(child: Text('Nothing here yet', style: TextStyle(color: PrairieColors.muted)));
          }
          final heroAutofocus = featured != null;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              if (featured != null)
                HomeHero(
                  items: featured.items,
                  serverUrl: session.serverUrl,
                  index: _heroIndex,
                  onIndexChange: (i) => setState(() => _heroIndex = i),
                  onOpenItem: _openItem,
                ),
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
                        autofocusFirst: !heroAutofocus && s == 0,
                      ),
                    if (onNow.isNotEmpty)
                      MediaRow<OnNowEntry>(
                        title: 'On now',
                        items: onNow,
                        itemBuilder: (context, entry, index) => _OnNowCard(
                          entry: entry,
                          serverUrl: session.serverUrl,
                          autofocus: !heroAutofocus && rows.isEmpty && index == 0,
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
          return LandscapeCard(
            title: item.title,
            subtitle: subtitle,
            meta: remaining != null ? '$remaining left' : null,
            imageUrl: item.backdropUrl ?? item.posterUrl,
            serverUrl: session.serverUrl,
            progress: item.progress,
            watched: item.userState?.played ?? false,
            autofocus: autofocusFirst && index == 0,
            onTap: () => _openItem(item),
          );
        },
      );
    }
    return MediaRow<CatalogItem>(
      title: section.title,
      items: section.items,
      itemBuilder: (context, item, index) => PosterCard(
        title: item.title,
        subtitle: item.subtitle,
        posterUrl: item.posterUrl,
        serverUrl: session.serverUrl,
        watched: item.userState?.played ?? false,
        favorite: item.userState?.isFavorite ?? false,
        progress: item.progress,
        autofocus: autofocusFirst && index == 0,
        onTap: () => _openItem(item),
      ),
    );
  }
}

class _OnNowCard extends StatelessWidget {
  const _OnNowCard({required this.entry, required this.serverUrl, required this.onTap, this.autofocus = false});

  final OnNowEntry entry;
  final String serverUrl;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final program = entry.program;
    final logoUrl = entry.channel.logoUrl;
    return InkWell(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(14),
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
                    if (logoUrl != null)
                      Image.network(
                        resolveAssetUrl(serverUrl, logoUrl),
                        fit: BoxFit.contain,
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
