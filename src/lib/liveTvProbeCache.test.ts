import { beforeEach, describe, expect, it } from "vitest";
import { loadCachedLiveTvAvailable, saveCachedLiveTvAvailable } from "./liveTvProbeCache";

beforeEach(() => {
  localStorage.clear();
});

describe("liveTvProbeCache", () => {
  it("returns null when nothing is stored", () => {
    expect(loadCachedLiveTvAvailable("https://tv.example.com")).toBeNull();
  });

  it("round-trips true and false per server", () => {
    saveCachedLiveTvAvailable("https://a.example.com", true);
    saveCachedLiveTvAvailable("https://b.example.com", false);
    expect(loadCachedLiveTvAvailable("https://a.example.com")).toBe(true);
    expect(loadCachedLiveTvAvailable("https://b.example.com")).toBe(false);
    expect(loadCachedLiveTvAvailable("https://c.example.com")).toBeNull();
  });
});
