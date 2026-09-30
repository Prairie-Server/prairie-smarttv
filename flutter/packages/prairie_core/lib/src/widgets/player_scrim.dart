import 'package:flutter/material.dart';

/// Full-screen dim between the video plane and the player UI.
///
/// While a stream is still loading, the native player usually shows a frozen
/// first frame; darkening it makes the loading indicator read as "not playing
/// yet" instead of as a paused picture. While the chrome is up, a lighter dim
/// keeps the player text legible over bright video.
class PlayerScrim extends StatelessWidget {
  const PlayerScrim({super.key, required this.loading, required this.chromeVisible});

  final bool loading;
  final bool chromeVisible;

  static const loadingOpacity = 0.6;
  static const chromeOpacity = 0.35;

  @override
  Widget build(BuildContext context) {
    final opacity = loading ? loadingOpacity : (chromeVisible ? chromeOpacity : 0.0);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 250),
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }
}
