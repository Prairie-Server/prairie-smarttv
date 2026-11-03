import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// The card that ends a capped Home row and opens the row's full page.
/// Shaped like the row's own cards ([landscape] for continue-style rows) and
/// focused like them, as an ordinary item at the end of the row.
class ExploreAllCard extends StatefulWidget {
  const ExploreAllCard({
    super.key,
    required this.onTap,
    this.landscape = false,
    this.autofocus = false,
    this.focusNode,
  });

  final VoidCallback onTap;
  final bool landscape;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<ExploreAllCard> createState() => _ExploreAllCardState();
}

class _ExploreAllCardState extends State<ExploreAllCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.landscape ? 14 : 16);
    return SizedBox(
      width: widget.landscape ? 280 : 140,
      child: InkWell(
        onTap: widget.onTap,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: radius,
        focusColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedScale(
          scale: _focused ? prairieCardFocusScale : 1.0,
          duration: prairieCardFocusDuration,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrairieColors.bgSoft.withValues(alpha: 0.72),
              borderRadius: radius,
              border: Border.all(
                color: _focused ? prairieCardFocusOutline : PrairieColors.ink.withValues(alpha: 0.1),
                width: _focused ? prairieCardFocusOutlineWidth : 1,
              ),
              boxShadow: _focused ? prairieCardFocusShadow : null,
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.arrow_forward, size: 28, color: PrairieColors.amber),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Explore all',
                    style: TextStyle(color: PrairieColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
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
