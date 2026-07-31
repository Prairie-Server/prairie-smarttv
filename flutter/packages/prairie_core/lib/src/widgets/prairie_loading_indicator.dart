import 'package:flutter/material.dart';

import '../theme/prairie_theme.dart';

/// Branded loading state: the Prairie mark pulsing behind a soft amber glow,
/// inside a spinning amber ring. Used everywhere the app would otherwise
/// show a bare `CircularProgressIndicator` for a full-screen or full-section
/// wait (small inline spinners — e.g. a "Signing in…" button icon — stay
/// plain; there's no room for the mark at that size).
class PrairieLoadingIndicator extends StatefulWidget {
  const PrairieLoadingIndicator({super.key, this.size = 108});

  final double size;

  @override
  State<PrairieLoadingIndicator> createState() => _PrairieLoadingIndicatorState();
}

class _PrairieLoadingIndicatorState extends State<PrairieLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              strokeWidth: widget.size * 0.045,
              valueColor: const AlwaysStoppedAnimation(PrairieColors.amber),
              backgroundColor: PrairieColors.amber.withValues(alpha: 0.15),
            ),
          ),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final scale = 0.92 + 0.08 * _pulse.value;
              final glow = 0.25 + 0.35 * _pulse.value;
              return Transform.scale(
                scale: scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: PrairieColors.amber.withValues(alpha: glow), blurRadius: widget.size * 0.35, spreadRadius: widget.size * 0.02)],
                  ),
                  child: child,
                ),
              );
            },
            child: ClipOval(
              child: Image.asset(
                'packages/prairie_core/assets/images/prairie-mark.png',
                width: widget.size * 0.5,
                height: widget.size * 0.5,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
