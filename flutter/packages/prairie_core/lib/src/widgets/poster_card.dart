import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// Shared poster card used by Home rails, Library/Collection grids, and
/// Search results. Mirrors `.poster-card` from styles.css: a bordered,
/// translucent card (not a bare image) with a 2:3 art area, watched
/// checkmark, favorite heart, in-progress bar, and a focus state that
/// scales up with an amber glow rather than Material's default ripple.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.posterUrl,
    required this.serverUrl,
    required this.onTap,
    this.watched = false,
    this.favorite = false,
    this.progress,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final String? posterUrl;
  final String serverUrl;
  final VoidCallback onTap;
  final bool watched;
  final bool favorite;
  final double? progress;
  final bool autofocus;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: widget.onTap,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: BorderRadius.circular(16),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: _focused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrairieColors.bgSoft.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused ? PrairieColors.ring : PrairieColors.ink.withValues(alpha: 0.1),
                width: _focused ? 3 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 14)),
                      ...prairieFocusRing(width: 3),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.posterUrl != null
                            ? Image.network(
                                resolveAssetUrl(widget.serverUrl, widget.posterUrl!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const PosterFallback(),
                              )
                            : const PosterFallback(),
                        if (widget.watched)
                          const Positioned(top: 6, right: 6, child: _Badge(icon: Icons.check, tooltip: 'Watched')),
                        if (widget.favorite)
                          Positioned(top: 6, right: widget.watched ? 34 : 6, child: const _Badge(icon: Icons.favorite, tooltip: 'Favorite')),
                        if (widget.progress != null && widget.progress! > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.progress,
                              minHeight: 4,
                              backgroundColor: Colors.black45,
                              valueColor: const AlwaysStoppedAnimation(PrairieColors.amber),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 11, 13, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PrairieColors.ink, fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                        if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PrairieColors.muted, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 14, color: PrairieColors.amber)),
      ),
    );
  }
}

class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: PrairieColors.bgSoft, child: Center(child: Icon(Icons.movie_outlined, color: PrairieColors.muted)));
  }
}

/// A responsive poster grid (Libraries/Collections/Search results). Mirrors
/// PosterGrid.tsx's CSS grid layout.
class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items, required this.serverUrl, required this.onOpen});

  final List<CatalogItem> items;
  final String serverUrl;
  final void Function(CatalogItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisExtent: 292, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return PosterCard(
          title: item.title,
          subtitle: item.subtitle,
          posterUrl: item.posterUrl,
          serverUrl: serverUrl,
          watched: item.userState?.played ?? false,
          favorite: item.userState?.isFavorite ?? false,
          progress: item.progress,
          autofocus: index == 0,
          onTap: () => onOpen(item),
        );
      },
    );
  }
}
