import '../api/quality_ladder.dart';

/// Decides when Auto quality should step down because playback keeps
/// buffering. A reduced port of the buffering-quality stall tracker the
/// web, Android and Apple players share, using the same constants:
///
/// - waits that start within [startupGrace] of a plan's first frame are the
///   plan's startup, not stalls;
/// - a stall shorter than [stallMin] is not counted;
/// - [stallsBeforeTrigger] counted stalls ended within [stallWindow], or one
///   stall lasting [longStall], trigger a step down;
/// - after the viewer restores quality, nothing triggers for [noLowerCooldown].
///
/// It performs no I/O: the player feeds it whether it is stalled (network
/// waits only, not seeks or pauses) and steps quality down when [update]
/// returns true.
class BufferingStallTracker {
  static const startupGrace = Duration(seconds: 10);
  static const stallMin = Duration(seconds: 1);
  static const stallsBeforeTrigger = 2;
  static const stallWindow = Duration(minutes: 2);
  static const longStall = Duration(seconds: 6);
  static const noLowerCooldown = Duration(minutes: 5);

  DateTime? _planStartedAt;
  DateTime? _stallStartedAt;
  bool _stallInGrace = false;
  bool _stallTriggered = false;
  final List<DateTime> _stallEnds = [];
  DateTime? _cooldownUntil;

  /// A new plan played its first frame: stall history starts over.
  void planStarted(DateTime now) {
    _planStartedAt = now;
    _stallStartedAt = null;
    _stallTriggered = false;
    _stallEnds.clear();
  }

  /// The viewer undid a step down (or picked a quality): don't lower again
  /// for [noLowerCooldown].
  void suppress(DateTime now) {
    _cooldownUntil = now.add(noLowerCooldown);
    _stallEnds.clear();
  }

  /// Counted stalls inside the window, for tests and diagnostics.
  int get countedStalls => _stallEnds.length;

  /// Feeds whether playback is [stalled] at [now]; true means step down now.
  bool update({required bool stalled, required DateTime now}) {
    final planStartedAt = _planStartedAt;
    if (planStartedAt == null) return false;
    final stallStartedAt = _stallStartedAt;
    if (stalled) {
      if (stallStartedAt == null) {
        _stallStartedAt = now;
        _stallInGrace = now.difference(planStartedAt) < startupGrace;
        _stallTriggered = false;
        return false;
      }
      if (!_stallInGrace && !_stallTriggered && now.difference(stallStartedAt) >= longStall) {
        _stallTriggered = true;
        return _trigger(now);
      }
      return false;
    }
    if (stallStartedAt == null) return false;
    _stallStartedAt = null;
    if (_stallInGrace || _stallTriggered || now.difference(stallStartedAt) < stallMin) return false;
    _stallEnds
      ..add(now)
      ..removeWhere((end) => now.difference(end) > stallWindow);
    if (_stallEnds.length < stallsBeforeTrigger) return false;
    return _trigger(now);
  }

  bool _trigger(DateTime now) {
    _stallEnds.clear();
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && now.isBefore(cooldownUntil)) return false;
    return true;
  }
}

/// The rung to step down to: the highest rung of [ladder] strictly below
/// [currentHeight] that the quality menu offers ([offeredIds]) — the richer
/// one when two share a height — or null when nothing lower is available or
/// the current height is unknown.
QualityLadderRung? bufferingStepDownRung(
  List<QualityLadderRung> ladder, {
  required int currentHeight,
  required Set<String> offeredIds,
}) {
  if (currentHeight <= 0) return null;
  QualityLadderRung? best;
  for (final rung in ladder) {
    if (rung.height <= 0 || rung.height >= currentHeight) continue;
    if (!offeredIds.contains(rung.id)) continue;
    if (best == null ||
        rung.height > best.height ||
        (rung.height == best.height && rung.bitrateKbps > best.bitrateKbps)) {
      best = rung;
    }
  }
  return best;
}
