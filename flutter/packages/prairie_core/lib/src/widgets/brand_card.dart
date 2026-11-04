import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// A studio, network or genre card on the Discover page: the brand's
/// gradient with its logo, or its name when it has no logo (genres) or the
/// logo fails to load. Landscape, focused like the other cards.
class BrandCard extends StatefulWidget {
  const BrandCard({super.key, required this.brand, required this.onTap, this.autofocus = false, this.focusNode});

  final DiscoverBrand brand;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<BrandCard> createState() => _BrandCardState();
}

class _BrandCardState extends State<BrandCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final from = parseBrandColor(brand.gradientFrom);
    final to = parseBrandColor(brand.gradientTo);
    final radius = BorderRadius.circular(14);
    final name = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        brand.displayName,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: Colors.white),
      ),
    );
    final logo = brand.logoUrl;
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 280,
        height: 158,
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(from ?? 0xFF2A2F3A), Color(to ?? from ?? 0xFF14171F)],
                ),
                borderRadius: radius,
                border: Border.all(
                  color: _focused ? prairieCardFocusOutline : PrairieColors.ink.withValues(alpha: 0.1),
                  width: _focused ? prairieCardFocusOutlineWidth : 1,
                ),
                boxShadow: _focused ? prairieCardFocusShadow : null,
              ),
              child: Center(
                child: logo == null
                    ? name
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                        child: Image.network(
                          logo,
                          fit: BoxFit.contain,
                          semanticLabel: brand.displayName,
                          errorBuilder: (_, _, _) => name,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
