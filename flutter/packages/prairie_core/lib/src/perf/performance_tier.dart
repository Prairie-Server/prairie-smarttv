import 'package:shared_preferences/shared_preferences.dart';

/// Device-tier visual budget for low-end Tizen/webOS SoCs.
///
/// Mirrors src/perf/performanceTier.ts. The TS version parses a browser user
/// agent string; there is no such string in a native Flutter app, so
/// [detectHardwareTier] instead takes structured hints (platform version,
/// RAM) that each platform app supplies from its own device-info plugin
/// (e.g. `device_info_plus_tizen`). The DOM-specific pieces of the original
/// (`applyPerformanceTier`'s `data-perf` attribute, the image-load-queue
/// side effect) have no Flutter equivalent and are dropped; callers should
/// read [resolvePerformanceTier] directly wherever those effects were read.
enum PerformanceTier { low, balanced, high }

/// `auto` defers to [detectHardwareTier]; the others force a tier.
enum PerformanceMode { auto, high, balanced, low }

const String performanceModeKey = 'prairie.performanceMode';
const PerformanceMode defaultPerformanceMode = PerformanceMode.auto;

const List<PerformanceTier> _tierOrder = [
  PerformanceTier.low,
  PerformanceTier.balanced,
  PerformanceTier.high,
];

/// Heuristic hardware tier from platform-supplied signals.
///
/// Mirrors `detectHardwareTier` in performanceTier.ts, replacing UA sniffing
/// with structured inputs: [platformVersion] is the OS version number (e.g.
/// Tizen 6.5 -> 6.5, webOS 6 -> 6), [physicalRamMb] and [cpuCores] are
/// optional hardware hints.
PerformanceTier detectHardwareTier({
  double? platformVersion,
  int? physicalRamMb,
  int? cpuCores,
  required TvPlatform platform,
}) {
  // ~2GB or less: same "low" cutoff as the TS `deviceMemory <= 2` check
  // (that field is in GB; TV device-info plugins tend to report MB).
  if (physicalRamMb != null && physicalRamMb > 0 && physicalRamMb <= 2048) {
    return PerformanceTier.low;
  }
  if (cpuCores != null && cpuCores > 0 && cpuCores <= 2) {
    return PerformanceTier.low;
  }

  if (platform == TvPlatform.tizen && platformVersion != null) {
    if (platformVersion < 6) return PerformanceTier.low;
    if (platformVersion < 7) return PerformanceTier.balanced;
    return PerformanceTier.high;
  }

  if (platform == TvPlatform.webos && platformVersion != null) {
    if (platformVersion <= 4) return PerformanceTier.low;
    if (platformVersion <= 5) return PerformanceTier.balanced;
    return PerformanceTier.high;
  }

  return PerformanceTier.high;
}

enum TvPlatform { tizen, webos }

Future<PerformanceMode> loadPerformanceMode(SharedPreferencesAsync prefs) async {
  final String? raw = await prefs.getString(performanceModeKey);
  return _parseMode(raw) ?? defaultPerformanceMode;
}

Future<PerformanceMode> savePerformanceMode(PerformanceMode mode, SharedPreferencesAsync prefs) async {
  await prefs.setString(performanceModeKey, mode.name);
  return mode;
}

PerformanceMode? _parseMode(String? raw) {
  if (raw == null) return null;
  for (final m in PerformanceMode.values) {
    if (m.name == raw) return m;
  }
  return null;
}

PerformanceTier resolvePerformanceTier(PerformanceMode mode, PerformanceTier detected) {
  if (mode == PerformanceMode.auto) return detected;
  return switch (mode) {
    PerformanceMode.high => PerformanceTier.high,
    PerformanceMode.balanced => PerformanceTier.balanced,
    PerformanceMode.low => PerformanceTier.low,
    PerformanceMode.auto => detected,
  };
}

bool prefersReducedEffects(PerformanceTier tier) =>
    tier == PerformanceTier.low || tier == PerformanceTier.balanced;

enum RasterFormat { avif, webp, png }

/// Only the high tier requests AVIF — AVIF decode is markedly slower than
/// WebP on TV SoCs, and mid-tier panels have enough cards on screen for that
/// difference to show up as scroll/input lag. Mirrors
/// `preferredRasterFormatsForTier`.
List<RasterFormat> preferredRasterFormatsForTier(PerformanceTier tier, List<RasterFormat> detected) {
  if (tier == PerformanceTier.high) return List.of(detected);
  return detected.where((f) => f != RasterFormat.avif).toList();
}

PerformanceMode cyclePerformanceMode(PerformanceMode mode) {
  const order = [
    PerformanceMode.auto,
    PerformanceMode.high,
    PerformanceMode.balanced,
    PerformanceMode.low,
  ];
  final index = order.indexOf(mode);
  return order[(index < 0 ? 0 : index + 1) % order.length];
}

String describePerformanceMode(PerformanceMode mode, PerformanceTier resolved) {
  if (mode == PerformanceMode.auto) return 'Auto (${resolved.name})';
  final name = mode.name;
  return name[0].toUpperCase() + name.substring(1);
}

int compareTiers(PerformanceTier a, PerformanceTier b) => _tierOrder.indexOf(a) - _tierOrder.indexOf(b);
