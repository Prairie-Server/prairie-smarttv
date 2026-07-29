import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

/// Mirrors HomeBrowseScreen.tsx's rails, minus continue-watching/hero (those
/// need watch.ts/userState.ts wiring into a dedicated widget).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<HomeSection>> _sections;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider)!;
    _sections = fetchHomeSections(ref.read(apiClientProvider), session);
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
          if (sections.isEmpty && onNow.isEmpty) {
            return const Center(child: Text('Nothing here yet', style: TextStyle(color: PrairieColors.muted)));
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            children: [
              if (onNow.isNotEmpty)
                MediaRow<OnNowEntry>(
                  title: 'On now',
                  items: onNow,
                  itemBuilder: (context, entry, index) => _OnNowCard(
                    entry: entry,
                    serverUrl: session.serverUrl,
                    autofocus: index == 0,
                    onTap: () => ref
                        .read(routeProvider.notifier)
                        .go(LiveTvPlayerRoute(channel: entry.channel, back: const HomeRoute())),
                  ),
                ),
              for (var s = 0; s < sections.length; s++)
                MediaRow<CatalogItem>(
                  title: sections[s].title,
                  items: sections[s].items,
                  itemBuilder: (context, item, index) => PosterCard(
                    title: item.title,
                    subtitle: item.subtitle,
                    posterUrl: item.posterUrl,
                    serverUrl: session.serverUrl,
                    watched: item.userState?.played ?? false,
                    favorite: item.userState?.isFavorite ?? false,
                    progress: item.progress,
                    autofocus: onNow.isEmpty && s == 0 && index == 0,
                    onTap: () => ref
                        .read(routeProvider.notifier)
                        .go(DetailRoute(contentId: item.contentId, seed: item, back: const HomeRoute())),
                  ),
                ),
            ],
          );
        },
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
