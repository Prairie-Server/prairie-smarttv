/// Timing for the player's one centered loading spinner: it appears only
/// once a wait has lasted [showDelay], and once shown it stays at least
/// [minVisible], so a short wait never flashes it and a wait that ends just
/// after it appears doesn't blink it away. Mirrors the shared timing the
/// Android and Apple players use (500 ms / 500 ms).
class LoadingSpinnerGate {
  LoadingSpinnerGate({
    this.showDelay = const Duration(milliseconds: 500),
    this.minVisible = const Duration(milliseconds: 500),
  });

  final Duration showDelay;
  final Duration minVisible;

  DateTime? _waitingSince;
  DateTime? _shownAt;

  /// Whether the spinner is on screen after the last [update].
  bool get visible => _shownAt != null;

  /// Feeds whether the player is [waiting] at [now]; returns whether the
  /// spinner shows.
  bool update({required bool waiting, required DateTime now}) {
    if (waiting) {
      final since = _waitingSince ??= now;
      if (_shownAt == null && now.difference(since) >= showDelay) _shownAt = now;
    } else {
      _waitingSince = null;
      final shownAt = _shownAt;
      if (shownAt != null && now.difference(shownAt) >= minVisible) _shownAt = null;
    }
    return visible;
  }

  /// How long until the spinner may change with no new input — the rest of
  /// the show delay, or the rest of the minimum on-screen time — or null when
  /// it only changes on input.
  Duration? nextChangeIn(DateTime now) {
    final since = _waitingSince;
    final shownAt = _shownAt;
    if (since != null && shownAt == null) return _atLeastZero(showDelay - now.difference(since));
    if (since == null && shownAt != null) return _atLeastZero(minVisible - now.difference(shownAt));
    return null;
  }

  static Duration _atLeastZero(Duration d) => d < Duration.zero ? Duration.zero : d;
}
