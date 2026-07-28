/**
 * Device-tier visual budget for low-end Tizen/webOS SoCs.
 * Auto detects capability; settings can force a mode.
 */

export type PerformanceTier = "high" | "balanced" | "low";
export type PerformanceMode = "auto" | PerformanceTier;

export const PERFORMANCE_MODE_KEY = "prairie.performanceMode";

export const DEFAULT_PERFORMANCE_MODE: PerformanceMode = "auto";

const TIER_ORDER: PerformanceTier[] = ["low", "balanced", "high"];

function isPerformanceMode(value: unknown): value is PerformanceMode {
  return value === "auto" || value === "high" || value === "balanced" || value === "low";
}

function isPerformanceTier(value: unknown): value is PerformanceTier {
  return value === "high" || value === "balanced" || value === "low";
}

/** Parse Tizen platform version from UA (e.g. Tizen 5.5 -> 5.5). */
export function parseTizenVersion(ua: string): number | null {
  const match = ua.match(/Tizen\s*([0-9]+(?:\.[0-9]+)?)/i);
  if (!match?.[1]) return null;
  const version = Number(match[1]);
  return Number.isFinite(version) ? version : null;
}

/**
 * Heuristic hardware tier from UA + optional memory/CPU signals.
 * Older Tizen / low memory -> low; mid TVs -> balanced; modern -> high.
 */
export function detectHardwareTier(
  ua: string = typeof navigator !== "undefined" ? navigator.userAgent : "",
  hints: { deviceMemory?: number; hardwareConcurrency?: number } = {},
): PerformanceTier {
  const memory =
    hints.deviceMemory ??
    (typeof navigator !== "undefined"
      ? (navigator as Navigator & { deviceMemory?: number }).deviceMemory
      : undefined);
  const cores =
    hints.hardwareConcurrency ??
    (typeof navigator !== "undefined" ? navigator.hardwareConcurrency : undefined);

  if (typeof memory === "number" && memory > 0 && memory <= 2) return "low";
  if (typeof cores === "number" && cores > 0 && cores <= 2) return "low";

  const tizen = parseTizenVersion(ua);
  if (tizen != null) {
    if (tizen < 6) return "low";
    if (tizen < 7) return "balanced";
    return "high";
  }

  if (/webOS\.TV|Web0S|WebOS/i.test(ua)) {
    const webos = ua.match(/Web[0O]S[/.]?(\d+)/i);
    const major = webos?.[1] ? Number(webos[1]) : NaN;
    if (Number.isFinite(major) && major <= 4) return "low";
    if (Number.isFinite(major) && major <= 5) return "balanced";
    return "high";
  }

  if (/SMART-TV|SmartTV|TV Safari|AppleTV/i.test(ua)) return "balanced";
  return "high";
}

export function loadPerformanceMode(
  storage: Pick<Storage, "getItem"> = localStorage,
): PerformanceMode {
  try {
    const raw = storage.getItem(PERFORMANCE_MODE_KEY);
    if (!raw) return DEFAULT_PERFORMANCE_MODE;
    const parsed = JSON.parse(raw) as unknown;
    if (isPerformanceMode(parsed)) return parsed;
    if (typeof parsed === "object" && parsed && "mode" in parsed) {
      const mode = (parsed as { mode: unknown }).mode;
      if (isPerformanceMode(mode)) return mode;
    }
  } catch {
    // ignore
  }
  return DEFAULT_PERFORMANCE_MODE;
}

export function savePerformanceMode(
  mode: PerformanceMode,
  storage: Pick<Storage, "setItem"> = localStorage,
): PerformanceMode {
  const next = isPerformanceMode(mode) ? mode : DEFAULT_PERFORMANCE_MODE;
  storage.setItem(PERFORMANCE_MODE_KEY, JSON.stringify(next));
  return next;
}

export function resolvePerformanceTier(
  mode: PerformanceMode = loadPerformanceMode(),
  detected: PerformanceTier = detectHardwareTier(),
): PerformanceTier {
  if (mode === "auto") return detected;
  return isPerformanceTier(mode) ? mode : detected;
}

/** Apply `data-perf` on <html> so CSS can dial effects. */
export function applyPerformanceTier(
  tier: PerformanceTier = resolvePerformanceTier(),
): PerformanceTier {
  document.documentElement.dataset.perf = tier;
  // Keep the artwork decode queue on the same budget as the visual tier —
  // settings used to update CSS alone and leave the queue at boot's value.
  void import("../lib/imageLoadQueue").then((mod) => {
    mod.refreshImageLoadConcurrency(tier);
  });
  return tier;
}

export function prefersReducedEffects(tier: PerformanceTier = resolvePerformanceTier()): boolean {
  return tier === "low" || tier === "balanced";
}

/**
 * Only the high tier requests AVIF. AVIF decode is markedly slower than WebP on
 * TV SoCs, and mid-tier panels (Tizen 6.x) have enough cards on screen for that
 * difference to show up as scroll and input lag.
 */
export function preferredRasterFormatsForTier(
  tier: PerformanceTier,
  detected: readonly ("avif" | "webp" | "png")[],
): Array<"avif" | "webp" | "png"> {
  if (tier === "high") return [...detected];
  return detected.filter((format) => format !== "avif");
}

export function cyclePerformanceMode(mode: PerformanceMode): PerformanceMode {
  const order: PerformanceMode[] = ["auto", "high", "balanced", "low"];
  const index = order.indexOf(mode);
  return order[index < 0 ? 0 : (index + 1) % order.length]!;
}

export function describePerformanceMode(mode: PerformanceMode, resolved: PerformanceTier): string {
  if (mode === "auto") return `Auto (${resolved})`;
  return mode.charAt(0).toUpperCase() + mode.slice(1);
}

export function compareTiers(a: PerformanceTier, b: PerformanceTier): number {
  return TIER_ORDER.indexOf(a) - TIER_ORDER.indexOf(b);
}
