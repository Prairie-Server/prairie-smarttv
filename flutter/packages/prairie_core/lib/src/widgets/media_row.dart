import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// A titled horizontal scroll rail of cards. Mirrors MediaRow.tsx.
class MediaRow<T> extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    this.variant = MediaRowVariant.poster,
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final MediaRowVariant variant;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final height = variant == MediaRowVariant.landscape ? 220.0 : 240.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
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
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) => itemBuilder(context, items[index], index),
            ),
          ),
        ],
      ),
    );
  }
}

enum MediaRowVariant { poster, landscape }
