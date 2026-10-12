import 'package:flutter/material.dart';

import '../theme/prairie_theme.dart';

/// Overrides the app theme's flat `IconButton`/`TextButton` foreground:
/// passing a plain `color:` locks the icon/text color for every state, but
/// the shared theme still flips these buttons' *background* to
/// [PrairieColors.ink] on D-pad focus — an ink icon on an ink background,
/// i.e. invisible. This keeps [color] unfocused and flips to
/// [PrairieColors.bg] focused, matching the background flip elsewhere.
ButtonStyle playerTransportStyle(Color color) => ButtonStyle(
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused) ? PrairieColors.bg : color,
  ),
);

/// The player's transport row: previous episode, skip back, play/pause,
/// skip forward, next episode, then [trailing] tools (audio, subtitles, …)
/// at the right edge. Play/pause stays centered whether or not the episode
/// buttons are present — each side is an equal-width [Expanded].
class PlayerTransportCluster extends StatelessWidget {
  const PlayerTransportCluster({
    super.key,
    required this.playFocus,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSkipBack,
    required this.onSkipForward,
    this.onPreviousEpisode,
    this.onNextEpisode,
    this.skipStep = const Duration(seconds: 10),
    this.trailing = const [],
  });

  final FocusNode playFocus;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  /// Null hides the button (not a series, or no episode on that side).
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;
  final Duration skipStep;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    final seconds = skipStep.inSeconds;
    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onPreviousEpisode != null) ...[
                IconButton(
                  iconSize: 32,
                  style: playerTransportStyle(PrairieColors.ink),
                  onPressed: onPreviousEpisode,
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous episode',
                ),
                const SizedBox(width: 8),
              ],
              TextButton(
                style: playerTransportStyle(PrairieColors.ink),
                onPressed: onSkipBack,
                child: Text('-${seconds}s', style: label),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        IconButton(
          focusNode: playFocus,
          autofocus: true,
          iconSize: 48,
          style: playerTransportStyle(PrairieColors.amber),
          onPressed: onPlayPause,
          icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
        ),
        Expanded(
          child: Row(
            children: [
              const SizedBox(width: 8),
              TextButton(
                style: playerTransportStyle(PrairieColors.ink),
                onPressed: onSkipForward,
                child: Text('+${seconds}s', style: label),
              ),
              if (onNextEpisode != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 32,
                  style: playerTransportStyle(PrairieColors.ink),
                  onPressed: onNextEpisode,
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next episode',
                ),
              ],
              const Spacer(),
              for (final (i, tool) in trailing.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                tool,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom-right pill over the video: "Skip Intro", "Watch Intro" (undo after
/// an auto-skip), "Skip Credits", … An optional [caption] sits above it.
class PlayerSkipButton extends StatelessWidget {
  const PlayerSkipButton({super.key, required this.label, required this.onPressed, this.focusNode, this.caption});

  final String label;
  final String? caption;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 4),
            child: Text(caption!, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
          ),
        _PlayerPillButton(label: label, onPressed: onPressed, focusNode: focusNode, icon: Icons.fast_forward),
      ],
    );
  }
}

/// "Up next" card shown over the credits / at the end of an episode.
/// [secondsLeft] null means no countdown (autoplay is off): the viewer
/// starts the next episode themselves.
class PlayerUpNextCard extends StatelessWidget {
  const PlayerUpNextCard({
    super.key,
    required this.episodeCode,
    required this.title,
    required this.onPlayNow,
    required this.onDismiss,
    this.secondsLeft,
    this.playFocus,
  });

  final String episodeCode;
  final String title;
  final int? secondsLeft;
  final VoidCallback onPlayNow;
  final VoidCallback onDismiss;
  final FocusNode? playFocus;

  @override
  Widget build(BuildContext context) {
    final left = secondsLeft;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2171717),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                left == null ? 'UP NEXT · $episodeCode' : 'UP NEXT IN ${left}s · $episodeCode',
                style: const TextStyle(color: PrairieColors.amber, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Fraunces', fontSize: 20, color: PrairieColors.ink),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PlayerPillButton(label: 'Play now', icon: Icons.skip_next, onPressed: onPlayNow, focusNode: playFocus),
                  const SizedBox(width: 10),
                  _PlayerPillButton(label: left == null ? 'Dismiss' : 'Cancel', onPressed: onDismiss),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerPillButton extends StatelessWidget {
  const _PlayerPillButton({required this.label, required this.onPressed, this.focusNode, this.icon});

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Focused: ink fill with bg-colored text, like the theme's other buttons.
    final style = playerTransportStyle(PrairieColors.ink).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? PrairieColors.ink : const Color(0xCC0A0C10),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
      shape: WidgetStatePropertyAll(StadiumBorder(side: BorderSide(color: PrairieColors.ink.withValues(alpha: 0.35)))),
    );
    const text = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    final iconData = icon;
    return iconData == null
        ? TextButton(focusNode: focusNode, style: style, onPressed: onPressed, child: Text(label, style: text))
        : TextButton.icon(
            focusNode: focusNode,
            style: style,
            onPressed: onPressed,
            icon: Icon(iconData, size: 20),
            label: Text(label, style: text),
          );
  }
}
