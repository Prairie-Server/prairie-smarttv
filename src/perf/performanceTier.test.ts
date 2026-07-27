import { afterEach, describe, expect, it } from "vitest";
import {
  applyPerformanceTier,
  compareTiers,
  cyclePerformanceMode,
  describePerformanceMode,
  detectHardwareTier,
  loadPerformanceMode,
  parseTizenVersion,
  preferredRasterFormatsForTier,
  prefersReducedEffects,
  resolvePerformanceTier,
  savePerformanceMode,
  type PerformanceMode,
} from "./performanceTier";

function memoryStorage(initial: Record<string, string> = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => {
      map.set(key, value);
    },
  };
}

describe("performanceTier", () => {
  afterEach(() => {
    document.documentElement.removeAttribute("data-perf");
  });

  it("parses Tizen versions from UA", () => {
    expect(parseTizenVersion("Mozilla/5.0 (SMART-TV; Tizen 5.5)")).toBe(5.5);
    expect(parseTizenVersion("Tizen 7.0")).toBe(7);
    expect(parseTizenVersion("Chrome")).toBeNull();
  });

  it("detects low/balanced/high tiers from Tizen year and memory", () => {
    expect(detectHardwareTier("Tizen 5.5", {})).toBe("low");
    expect(detectHardwareTier("Tizen 6.5", {})).toBe("balanced");
    expect(detectHardwareTier("Tizen 8.0", {})).toBe("high");
    expect(detectHardwareTier("Desktop Chrome", { deviceMemory: 2 })).toBe("low");
    expect(detectHardwareTier("Desktop Chrome", { hardwareConcurrency: 8 })).toBe("high");
  });

  it("resolves auto vs forced modes", () => {
    expect(resolvePerformanceTier("auto", "low")).toBe("low");
    expect(resolvePerformanceTier("high", "low")).toBe("high");
    expect(resolvePerformanceTier("balanced", "high")).toBe("balanced");
  });

  it("persists performance mode and applies data-perf", () => {
    const storage = memoryStorage();
    expect(savePerformanceMode("low", storage)).toBe("low");
    expect(loadPerformanceMode(storage)).toBe("low");
    expect(applyPerformanceTier("balanced")).toBe("balanced");
    expect(document.documentElement.dataset.perf).toBe("balanced");
  });

  it("strips AVIF on low tier and cycles modes", () => {
    expect(preferredRasterFormatsForTier("low", ["avif", "webp", "png"])).toEqual([
      "webp",
      "png",
    ]);
    expect(preferredRasterFormatsForTier("high", ["avif", "webp", "png"])).toEqual([
      "avif",
      "webp",
      "png",
    ]);
    expect(cyclePerformanceMode("auto")).toBe("high");
    expect(cyclePerformanceMode("low")).toBe("auto");
    expect(describePerformanceMode("auto", "balanced")).toBe("Auto (balanced)");
    expect(describePerformanceMode("high", "high")).toBe("High");
    expect(compareTiers("low", "high")).toBeLessThan(0);
  });

  it("loads object-shaped mode blobs and ignores corrupt storage", () => {
    expect(loadPerformanceMode(memoryStorage({ "prairie.performanceMode": '{"mode":"balanced"}' }))).toBe(
      "balanced",
    );
    expect(loadPerformanceMode(memoryStorage({ "prairie.performanceMode": '{"mode":"nope"}' }))).toBe(
      "auto",
    );
    expect(loadPerformanceMode(memoryStorage({ "prairie.performanceMode": "{" }))).toBe("auto");
    expect(loadPerformanceMode(memoryStorage({ "prairie.performanceMode": '"nope"' }))).toBe("auto");
    expect(savePerformanceMode("nope" as PerformanceMode, memoryStorage())).toBe("auto");
    expect(resolvePerformanceTier("nope" as PerformanceMode, "balanced")).toBe("balanced");
  });

  it("detects webOS and low core counts, and reports reduced effects", () => {
    expect(detectHardwareTier("Mozilla/5.0 Web0S/3.0", {})).toBe("low");
    expect(detectHardwareTier("Mozilla/5.0 Web0S/5.0", {})).toBe("balanced");
    expect(detectHardwareTier("Mozilla/5.0 Web0S/6.0", {})).toBe("high");
    expect(detectHardwareTier("Mozilla/5.0 WebOS TV", {})).toBe("high");
    expect(detectHardwareTier("SMART-TV", { hardwareConcurrency: 8 })).toBe("balanced");
    expect(detectHardwareTier("Desktop", { hardwareConcurrency: 2 })).toBe("low");
    expect(detectHardwareTier("Desktop", { deviceMemory: 1 })).toBe("low");
    expect(prefersReducedEffects("low")).toBe(true);
    expect(prefersReducedEffects("balanced")).toBe(true);
    expect(prefersReducedEffects("high")).toBe(false);
  });
});
