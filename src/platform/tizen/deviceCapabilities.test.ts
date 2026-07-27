import { describe, expect, it, vi, afterEach } from "vitest";

vi.mock("./avplay", () => ({
  isAvPlayAvailable: vi.fn(() => false),
}));

import { isAvPlayAvailable } from "./avplay";
import { probeSupportedAudioCodecs, probeTvPlaybackCapabilities } from "./deviceCapabilities";

function stubWindow(partial: {
  innerWidth: number;
  innerHeight: number;
  matchMedia?: ((query: string) => { matches: boolean }) | undefined;
  webapis?: unknown;
}): void {
  vi.stubGlobal("window", {
    innerWidth: partial.innerWidth,
    innerHeight: partial.innerHeight,
    matchMedia: partial.matchMedia,
    webapis: partial.webapis,
  });
}

describe("probeTvPlaybackCapabilities", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.mocked(isAvPlayAvailable).mockReturnValue(false);
  });

  it("advertises hevc and mkv when AVPlay is available", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 3840, height: 2160 });
    stubWindow({
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
    expect(caps.codecs_audio).toEqual(["aac", "ac3", "eac3", "mp3"]);
  });

  it("maps 1080p and 1440p panels from screen size", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 5.0)" });
    vi.stubGlobal("screen", { width: 1920, height: 1080 });
    stubWindow({
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
    stubWindow({
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
    stubWindow({
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
    stubWindow({
      innerWidth: 1280,
      innerHeight: 720,
      matchMedia: undefined,
    });
    const caps = probeTvPlaybackCapabilities();
    expect(caps.containers).toContain("mkv");
    expect(caps.codecs_video).toContain("hevc");
    expect(caps.hdr).toBe(false);
    expect(caps.codecs_audio).toContain("dts");
  });

  it("stays conservative without AVPlay on unknown UA", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0" });
    vi.stubGlobal("screen", { width: 1280, height: 720 });
    stubWindow({
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

  it("advertises TrueHD only when systeminfo reports support", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 7.0)" });
    const supported = new Set(["AAC", "AC3", "E-AC3", "TrueHD", "MPEG"]);
    const caps = probeSupportedAudioCodecs({
      tizenMajor: 7,
      systemInfo: {
        isSupportedAudioCodec: (name) => supported.has(name),
      },
    });
    expect(caps).toContain("truehd");
    expect(caps).toContain("aac");
    expect(caps).not.toContain("dts");
    expect(caps).not.toContain("opus");
  });

  it("omits TrueHD when the TV reports it unsupported", () => {
    const caps = probeSupportedAudioCodecs({
      tizenMajor: 6,
      systemInfo: {
        isSupportedAudioCodec: (name) => name !== "TrueHD" && name !== "OPUS" && name !== "AC4",
      },
    });
    expect(caps).not.toContain("truehd");
    expect(caps).toEqual(expect.arrayContaining(["aac", "ac3", "eac3", "mp3"]));
  });

  it("tolerates probe throws and keeps the baseline set", () => {
    const caps = probeSupportedAudioCodecs({
      tizenMajor: 6,
      systemInfo: {
        isSupportedAudioCodec: () => {
          throw new Error("bridge down");
        },
      },
    });
    expect(caps).toEqual(["aac", "ac3", "eac3", "mp3"]);
  });

  it("falls back to baseline (plus DTS on old Tizen) without a probe API", () => {
    expect(probeSupportedAudioCodecs({ tizenMajor: 6, systemInfo: null })).toEqual([
      "aac",
      "ac3",
      "eac3",
      "mp3",
    ]);
    expect(probeSupportedAudioCodecs({ tizenMajor: 3, systemInfo: {} })).toContain("dts");
    expect(probeSupportedAudioCodecs({ tizenMajor: 3, systemInfo: null })).toContain("dts");
  });
});
