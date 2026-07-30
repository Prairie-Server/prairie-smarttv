import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:prairie_core/prairie_core.dart';

/// A titled horizontal scroll rail of cards. Mirrors MediaRow.tsx.
class MediaRow<T> extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.variant = MediaRowVariant.poster,
    this.escapeUpFocusNode,
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final MediaRowVariant variant;
  /// Explicit fallback focus target for arrow-up when Flutter's geometric
  /// directional search can't find anything above this row (e.g. a rail
  /// sitting directly under a page hero) — the search is unreliable enough
  /// on real hardware that it can't be trusted as the only path back up.
  final FocusNode? escapeUpFocusNode;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    // Must fit card art + title/subtitle below — 240px clipped poster titles
    // (2:3 art alone is ~210px on a 140-wide card). Extra vertical padding
    // leaves room for the focused card's scale + amber ring without clipping.
    final height = variant == MediaRowVariant.landscape ? 284.0 : 308.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            // Arrow-up from a nested horizontal rail must leave the row for the
            // vertical page (detail hero / previous rail), not get trapped.
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey != LogicalKeyboardKey.arrowUp &&
                    event.logicalKey != LogicalKeyboardKey.arrowDown) {
                  return KeyEventResult.ignored;
                }
                final direction = event.logicalKey == LogicalKeyboardKey.arrowUp
                    ? TraversalDirection.up
                    : TraversalDirection.down;
                // Use the actually-focused card's rect, not this wrapper
                // node's (which spans the full row width) — the wrapper's
                // rect makes the geometric search unreliable, especially
                // for "up" out of the last row on the page.
                final focused = FocusManager.instance.primaryFocus;
                var handled = focused?.focusInDirection(direction) ?? false;
                if (!handled && direction == TraversalDirection.up && escapeUpFocusNode != null) {
                  escapeUpFocusNode!.requestFocus();
                  handled = true;
                }
                return handled ? KeyEventResult.handled : KeyEventResult.ignored;
              },
              child: ListView.separated(
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) => itemBuilder(context, items[index], index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum MediaRowVariant { poster, landscape }
