import { describe, expect, it } from "vitest";
import {
  DEFAULT_PLAYBACK_SETTINGS,
  loadPlaybackSettings,
  normalizePlaybackSettings,
  resolveForcedPlayMethod,
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
      },
      storage,
    );
    expect(saved.playerBackend).toBe("native");
    expect(loadPlaybackSettings(storage)).toEqual(saved);
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
});
