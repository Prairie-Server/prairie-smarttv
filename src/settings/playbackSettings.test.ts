import { describe, expect, it } from "vitest";
import {
  DEFAULT_PLAYBACK_SETTINGS,
  describePlayMethodPreference,
  loadPlaybackSettings,
  normalizePlaybackSettings,
  resolveForcedPlayMethod,
  resolvePreferredSubtitleIndex,
  savePlaybackSettings,
} from "./playbackSettings";

function memoryStorage(initial: Record<string, string> = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => {
      map.set(key, value);
    },
    removeItem: (key: string) => {
      map.delete(key);
    },
  };
}

describe("playbackSettings", () => {
  it("defaults to auto backend with no forced play method", () => {
    expect(DEFAULT_PLAYBACK_SETTINGS.playerBackend).toBe("auto");
    expect(resolveForcedPlayMethod(DEFAULT_PLAYBACK_SETTINGS)).toBeNull();
  });

  it("persists and reloads from localStorage-like storage", () => {
    const storage = memoryStorage();
    const saved = savePlaybackSettings(
      {
        playerBackend: "native",
        forceDirectPlay: true,
        forceTranscode: false,
        preferredSubtitleLanguage: "eng",
        subtitleAppearance: {
          ...DEFAULT_PLAYBACK_SETTINGS.subtitleAppearance,
          fontSize: "xlarge",
          backgroundStyle: "box",
          backgroundOpacity: 50,
        },
      },
      storage,
    );
    expect(saved.playerBackend).toBe("native");
    expect(saved.preferredSubtitleLanguage).toBe("eng");
    expect(saved.subtitleAppearance.fontSize).toBe("xlarge");
    expect(loadPlaybackSettings(storage)).toEqual(saved);
  });

  it("upgrades older settings blobs missing subtitle fields", () => {
    const storage = memoryStorage({
      "prairie.playbackSettings": JSON.stringify({
        playerBackend: "html5",
        forceDirectPlay: false,
        forceTranscode: false,
      }),
    });
    const loaded = loadPlaybackSettings(storage);
    expect(loaded.playerBackend).toBe("html5");
    expect(loaded.subtitleAppearance.fontSize).toBe("large");
    expect(loaded.preferredSubtitleLanguage).toBe("");
  });

  it("prefers force direct over force transcode when both set", () => {
    const normalized = normalizePlaybackSettings({
      forceDirectPlay: true,
      forceTranscode: true,
    });
    expect(normalized.forceDirectPlay).toBe(true);
    expect(normalized.forceTranscode).toBe(false);
    expect(resolveForcedPlayMethod(normalized)).toBe("direct");
  });

  it("returns transcode when only forceTranscode is enabled", () => {
    expect(
      resolveForcedPlayMethod({
        ...DEFAULT_PLAYBACK_SETTINGS,
        playerBackend: "html5",
        forceDirectPlay: false,
        forceTranscode: true,
      }),
    ).toBe("transcode");
  });

  it("recovers from corrupt storage", () => {
    const storage = memoryStorage({ "prairie.playbackSettings": "{not-json" });
    expect(loadPlaybackSettings(storage)).toEqual(DEFAULT_PLAYBACK_SETTINGS);
  });

  it("rejects malformed persisted booleans instead of coercing truthy strings", () => {
    const normalized = normalizePlaybackSettings({
      // @ts-expect-error intentional malformed persisted values
      forceDirectPlay: "false",
      // @ts-expect-error intentional malformed persisted values
      forceTranscode: "true",
    });
    expect(normalized.forceDirectPlay).toBe(false);
    expect(normalized.forceTranscode).toBe(false);
    expect(resolveForcedPlayMethod(normalized)).toBeNull();
  });

  it("resolves preferred subtitle language index", () => {
    const tracks = [{ language: "spa" }, { language: "eng" }, { language: "eng-US" }];
    expect(resolvePreferredSubtitleIndex(tracks, "")).toBe(-1);
    expect(resolvePreferredSubtitleIndex([], "eng")).toBe(-1);
    expect(resolvePreferredSubtitleIndex(tracks, "eng")).toBe(1);
    expect(resolvePreferredSubtitleIndex(tracks, "eng-us")).toBe(2);
    expect(resolvePreferredSubtitleIndex(tracks, "en")).toBe(1);
    expect(resolvePreferredSubtitleIndex(tracks, "deu")).toBe(-1);
    expect(resolvePreferredSubtitleIndex([{ index: 0 }], "eng")).toBe(-1);
  });

  it("normalizes invalid backends and non-string preferred language", () => {
    const normalized = normalizePlaybackSettings({
      // @ts-expect-error intentional malformed
      playerBackend: "flash",
      // @ts-expect-error intentional malformed
      preferredSubtitleLanguage: 12,
    });
    expect(normalized.playerBackend).toBe("auto");
    expect(normalized.preferredSubtitleLanguage).toBe("");
    expect(normalizePlaybackSettings(null).playerBackend).toBe("auto");
    expect(describePlayMethodPreference(DEFAULT_PLAYBACK_SETTINGS)).toBe("auto");
    expect(
      describePlayMethodPreference({
        ...DEFAULT_PLAYBACK_SETTINGS,
        forceTranscode: true,
      }),
    ).toBe("transcode");
  });

  it("returns defaults when storage is empty", () => {
    expect(loadPlaybackSettings(memoryStorage())).toEqual(DEFAULT_PLAYBACK_SETTINGS);
  });
});
