import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// Featured hero carousel — mirrors HomeHero.tsx / `.home-hero` CSS.
class HomeHero extends StatefulWidget {
  const HomeHero({
    super.key,
    required this.items,
    required this.serverUrl,
    required this.index,
    required this.onIndexChange,
    required this.onOpenItem,
    this.autofocusPlay = true,
    this.playFocusNode,
  });

  final List<CatalogItem> items;
  final String serverUrl;
  final int index;
  final ValueChanged<int> onIndexChange;
  final void Function(CatalogItem item) onOpenItem;
  final bool autofocusPlay;
  final FocusNode? playFocusNode;

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final len = widget.items.length;
    final safeIndex = ((widget.index % len) + len) % len;
    final item = widget.items[safeIndex];
    final backdrop = (item.backdropUrl?.trim().isNotEmpty == true) ? item.backdropUrl : item.posterUrl;
    final heroHeight = (MediaQuery.sizeOf(context).height * 0.62).clamp(320.0, 560.0);

    return SizedBox(
      height: heroHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: PrairieColors.bgElevated,
            child: backdrop != null
                ? Image.network(
                    resolveAssetUrl(widget.serverUrl, backdrop),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(color: PrairieColors.bgElevated),
                  )
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF243041), PrairieColors.bg],
                      ),
                    ),
                  ),
          ),
          // Mirrors `.home-hero__shade`: left + bottom darkening.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF0A0C10).withValues(alpha: 0.92),
                  const Color(0xFF0A0C10).withValues(alpha: 0.45),
                  Colors.transparent,
                ],
                stops: const [0.12, 0.52, 0.78],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF0A0C10).withValues(alpha: 0.95),
                  const Color(0xFF0A0C10).withValues(alpha: 0.35),
                  Colors.transparent,
                ],
                stops: const [0.08, 0.48, 0.72],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 736),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      len > 1 ? 'Featured · ${safeIndex + 1} of $len' : 'Featured',
                      style: const TextStyle(color: PrairieColors.amber, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.04),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'Fraunces', fontSize: 40, height: 1.05, color: PrairieColors.ink, letterSpacing: -0.5),
                    ),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(item.subtitle!, style: TextStyle(color: PrairieColors.ink.withValues(alpha: 0.88), fontWeight: FontWeight.w500)),
                    ],
                    if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.overview!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PrairieColors.muted, height: 1.5),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          focusNode: widget.playFocusNode,
                          autofocus: widget.autofocusPlay,
                          onPressed: () => widget.onOpenItem(item),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('More Info'),
                        ),
                        if (len > 1) ...[
                          OutlinedButton(
                            onPressed: () => widget.onIndexChange((safeIndex - 1 + len) % len),
                            child: const Text('Prev'),
                          ),
                          OutlinedButton(
                            onPressed: () => widget.onIndexChange((safeIndex + 1) % len),
                            child: const Text('Next'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
