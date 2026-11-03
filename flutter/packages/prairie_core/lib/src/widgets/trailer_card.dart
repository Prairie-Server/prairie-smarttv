import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';
import 'package:prairie_core/src/lib/thumbhash.dart';
import 'package:prairie_core/src/lib/trailer_rail.dart';
import 'package:prairie_core/src/platform/youtube_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A 16:9 card in a title page's Trailers & Extras rail: the still (or its
/// ThumbHash while it loads), the title, and `YouTube` or the runtime below.
class TrailerCard extends StatefulWidget {
  const TrailerCard({super.key, required this.entry, required this.serverUrl, required this.onTap, this.focusNode});

  final TrailerRailEntry entry;
  final String serverUrl;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<TrailerCard> createState() => _TrailerCardState();
}

class _TrailerCardState extends State<TrailerCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final secondary = trailerRailSecondaryLine(entry);
    final placeholder = ThumbHashImage(
      hash: entry.thumbhash,
      fallback: Center(
        child: Icon(entry is YouTubeTrailerEntry ? Icons.smart_display_outlined : Icons.movie_outlined, color: PrairieColors.muted),
      ),
    );
    final thumbnail = entry.thumbnailUrl;
    return SizedBox(
      width: 280,
      child: InkWell(
        onTap: widget.onTap,
        focusNode: widget.focusNode,
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: BorderRadius.circular(14),
        focusColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: _focused ? prairieCardFocusScale : 1.0,
          duration: prairieCardFocusDuration,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrairieColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused ? prairieCardFocusOutline : PrairieColors.ink.withValues(alpha: 0.1),
                width: _focused ? prairieCardFocusOutlineWidth : 1,
              ),
              boxShadow: _focused ? prairieCardFocusShadow : null,
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
                        placeholder,
                        if (thumbnail != null && thumbnail.trim().isNotEmpty)
                          Builder(
                            builder: (context) {
                              final dpr = MediaQuery.devicePixelRatioOf(context);
                              // A YouTube still is an absolute URL; a local
                              // extra's is presigned on this server.
                              final url = entry is YouTubeTrailerEntry
                                  ? thumbnail
                                  : artworkSized(resolveAssetUrl(widget.serverUrl, thumbnail), landscapeArtworkWidth);
                              return Image.network(
                                url,
                                fit: BoxFit.cover,
                                cacheWidth: (280 * dpr).round(),
                                cacheHeight: (157 * dpr).round(),
                                // The placeholder underneath stays visible.
                                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                                    frame == null && !wasSynchronouslyLoaded ? const SizedBox.shrink() : child,
                                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                              );
                            },
                          ),
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: _focused ? 0.55 : 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                entry is YouTubeTrailerEntry ? Icons.open_in_new : Icons.play_arrow,
                                size: _focused ? 30 : 24,
                                color: Colors.white,
                              ),
                            ),
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
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PrairieColors.ink, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
                        ),
                        if (secondary != null)
                          Text(secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
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

/// Hands [entry] to the TV's YouTube app at its watch-page link. When the TV
/// has no YouTube app, or the launch fails, shows the link as a QR code to
/// watch on a phone instead.
Future<void> openYouTubeTrailer(BuildContext context, WidgetRef ref, YouTubeTrailerEntry entry) async {
  final videoId = entry.video.siteKey.trim();
  final watchUrl = youTubeWatchUrl(videoId);
  final launcher = ref.read(youTubeLauncherProvider);
  final opened = launcher != null && await launcher.openWatchPage(videoId: videoId, watchUrl: watchUrl);
  if (opened || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: PrairieColors.bgElevated,
      title: Text(entry.title, style: const TextStyle(color: PrairieColors.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "This TV couldn't open YouTube. Scan the code to watch on your phone.",
            style: TextStyle(color: PrairieColors.muted),
          ),
          const SizedBox(height: 16),
          QrImageView(data: watchUrl, size: 180, backgroundColor: Colors.white),
          const SizedBox(height: 12),
          SelectableText(watchUrl, style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}
