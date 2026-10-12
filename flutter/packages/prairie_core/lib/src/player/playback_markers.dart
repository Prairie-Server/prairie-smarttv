/// Skippable segment kinds the server detects (`MarkerOccurrence.kind`).
enum MarkerKind { intro, credits, recap, preview }

/// One marker occurrence in source time, seconds. Mirrors web
/// `MarkerRegionView` without the thumbnail fields.
class MarkerRegion {
  const MarkerRegion({required this.kind, required this.start, required this.end});

  final MarkerKind kind;
  final double start;
  final double end;

  bool contains(double seconds) => seconds >= start && seconds < end;

  /// Stable identity for "already skipped / already prompted" bookkeeping.
  String get key => '${kind.name}:$start:$end';

  @override
  bool operator ==(Object other) => other is MarkerRegion && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

/// Marker regions of one watch-detail file version. Mirrors web
/// `resolveMarkerRegions`: prefers v2 `marker_segments` (every occurrence),
/// falling back to the singular `intro`/`credits`/`recap`/`preview` ranges —
/// `{start_seconds, end_seconds}` on v2, `{start, end}` on v1. Drops invalid
/// ranges and sorts by start.
List<MarkerRegion> parseMarkerRegions(Map<String, dynamic> version) {
  final regions = <MarkerRegion>[];
  final segments = version['marker_segments'];
  if (segments is List) {
    for (final raw in segments) {
      if (raw is! Map) continue;
      final kind = _kindNamed(raw['kind']);
      final start = (raw['start_seconds'] as num?)?.toDouble();
      final end = (raw['end_seconds'] as num?)?.toDouble();
      if (kind != null && start != null && end != null) regions.add(MarkerRegion(kind: kind, start: start, end: end));
    }
  } else {
    for (final kind in MarkerKind.values) {
      final raw = version[kind.name];
      if (raw is! Map) continue;
      final start = ((raw['start_seconds'] ?? raw['start']) as num?)?.toDouble();
      final end = ((raw['end_seconds'] ?? raw['end']) as num?)?.toDouble();
      if (start != null && end != null) regions.add(MarkerRegion(kind: kind, start: start, end: end));
    }
  }
  return regions.where((r) => r.start.isFinite && r.end.isFinite && r.start >= 0 && r.end > r.start).toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
}

MarkerKind? _kindNamed(Object? name) {
  for (final kind in MarkerKind.values) {
    if (kind.name == name) return kind;
  }
  return null;
}

/// The region of [kind] the playhead is inside, if any.
MarkerRegion? activeMarker(List<MarkerRegion> regions, MarkerKind kind, double seconds) {
  for (final region in regions) {
    if (region.kind == kind && region.contains(seconds)) return region;
  }
  return null;
}

/// Where "up next" starts: the trailing run of credits (and, when
/// [allowPreview], next-episode preview) markers that reaches the end, so
/// the episode is only left once every unmarked scene has played. Mirrors
/// web `resolveAutoplayMarker`, including its 1s rounding allowance; returns
/// the start in seconds, or null when nothing trailing is marked.
double? autoplayRegionStart(List<MarkerRegion> regions, double durationSeconds, {required bool allowPreview}) {
  if (durationSeconds <= 0) return null;
  var start = durationSeconds;
  for (final region in regions.reversed) {
    if (region.kind != MarkerKind.credits && !(allowPreview && region.kind == MarkerKind.preview)) continue;
    if (region.end >= start - 1 && region.start < start) start = region.start;
  }
  return start < durationSeconds ? start : null;
}
