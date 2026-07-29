import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// Landscape (16:9) continue-watching card — mirrors LandscapeCard.tsx.
class LandscapeCard extends StatefulWidget {
  const LandscapeCard({
    super.key,
    required this.title,
    required this.serverUrl,
    required this.onTap,
    this.subtitle,
    this.meta,
    this.imageUrl,
    this.progress,
    this.watched = false,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final String? imageUrl;
  final String serverUrl;
  final double? progress;
  final bool watched;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<LandscapeCard> createState() => _LandscapeCardState();
}

class _LandscapeCardState extends State<LandscapeCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: InkWell(
        onTap: widget.onTap,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: BorderRadius.circular(14),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: _focused ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrairieColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? PrairieColors.ring : PrairieColors.ink.withValues(alpha: 0.1),
                width: _focused ? 3 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 28, offset: const Offset(0, 12)),
                      ...prairieFocusRing(width: 3),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xFF10151C)),
                        if (widget.imageUrl != null && widget.imageUrl!.trim().isNotEmpty)
                          Image.network(
                            resolveAssetUrl(widget.serverUrl, widget.imageUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.play_arrow, size: 28, color: PrairieColors.muted)),
                          )
                        else
                          const Center(child: Icon(Icons.play_arrow, size: 28, color: PrairieColors.muted)),
                        if (_focused)
                          ColoredBox(
                            color: const Color(0xFF0A0C10).withValues(alpha: 0.18),
                            child: const Center(child: Icon(Icons.play_arrow, size: 36, color: Colors.white)),
                          ),
                        if (widget.watched)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A0C10).withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                child: Text('Watched', style: TextStyle(color: PrairieColors.amber, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        if (widget.progress != null && widget.progress! > 0.02 && widget.progress! < 0.95)
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
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                          Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PrairieColors.ink, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                        if (widget.meta != null && widget.meta!.isNotEmpty)
                          Text(widget.meta!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
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
