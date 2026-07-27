import { describe, expect, it, vi, afterEach } from "vitest";

vi.mock("./avplay", () => ({
  isAvPlayAvailable: vi.fn(() => false),
}));

import { isAvPlayAvailable } from "./avplay";
import { probeTvPlaybackCapabilities } from "./deviceCapabilities";

describe("probeTvPlaybackCapabilities", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.mocked(isAvPlayAvailable).mockReturnValue(false);
  });

  it("advertises hevc and mkv when AVPlay is available", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 3840, height: 2160 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 1920,
      innerHeight: 1080,
      matchMedia: () => ({ matches: true }),
    });
    const caps = probeTvPlaybackCapabilities({ avplayAvailable: true });
    expect(caps.codecs_video).toContain("h264");
    expect(caps.codecs_video).toContain("hevc");
    expect(caps.containers).toContain("mkv");
    expect(caps.max_resolution).toBe("2160p");
    expect(caps.hdr).toBe(true);
  });

  it("maps 1080p and 1440p panels from screen size", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 5.0)" });
    vi.stubGlobal("screen", { width: 1920, height: 1080 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 1920,
      innerHeight: 1080,
      matchMedia: () => ({ matches: false }),
    });
    expect(probeTvPlaybackCapabilities({ avplayAvailable: true }).max_resolution).toBe("1080p");

    vi.stubGlobal("screen", { width: 2560, height: 1440 });
    expect(probeTvPlaybackCapabilities({ avplayAvailable: true }).max_resolution).toBe("1440p");
  });

  it("uses window size when screen reports zero", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 3.0)" });
    vi.stubGlobal("screen", { width: 0, height: 0 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 3840,
      innerHeight: 2160,
      matchMedia: () => ({ matches: false }),
    });
    const caps = probeTvPlaybackCapabilities({ avplayAvailable: false });
    expect(caps.max_resolution).toBe("2160p");
    expect(caps.codecs_video).toContain("hevc");
    expect(caps.hdr).toBe(false);
  });

  it("enables hevc from Tizen major even without AVPlay", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 4.0)" });
    vi.stubGlobal("screen", { width: 1280, height: 720 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 1280,
      innerHeight: 720,
      matchMedia: () => {
        throw new Error("matchMedia unavailable");
      },
    });
    const caps = probeTvPlaybackCapabilities({ avplayAvailable: false });
    expect(caps.codecs_video).toContain("hevc");
    expect(caps.containers).not.toContain("mkv");
    expect(caps.hdr).toBe(true);
  });

  it("defers to isAvPlayAvailable when override is omitted", () => {
    vi.mocked(isAvPlayAvailable).mockReturnValue(true);
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 2.4)" });
    vi.stubGlobal("screen", { width: 1280, height: 720 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 1280,
      innerHeight: 720,
      matchMedia: undefined,
    });
    const caps = probeTvPlaybackCapabilities();
    expect(caps.containers).toContain("mkv");
    expect(caps.codecs_video).toContain("hevc");
    expect(caps.hdr).toBe(false);
  });

  it("stays conservative without AVPlay on unknown UA", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0" });
    vi.stubGlobal("screen", { width: 1280, height: 720 });
    vi.stubGlobal("window", {
      ...window,
      innerWidth: 1280,
      innerHeight: 720,
      matchMedia: () => ({ matches: false }),
    });
    const caps = probeTvPlaybackCapabilities({ avplayAvailable: false });
    expect(caps.codecs_video).toEqual(["h264"]);
    expect(caps.containers).not.toContain("mkv");
    expect(caps.max_resolution).toBe("720p");
    expect(caps.hdr).toBe(false);
  });
});
