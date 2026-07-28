import { describe, expect, it, vi, afterEach } from "vitest";

vi.mock("./avplay", () => ({
  isAvPlayAvailable: vi.fn(() => false),
}));

import { isAvPlayAvailable } from "./avplay";
import {
  applyAv1AdvertiseOverrides,
  probeAv1Support,
  probeSupportedAudioCodecs,
  probeTvPlaybackCapabilities,
  resolveAdvertisedCapabilities,
  tizenPlatformVersion,
} from "./deviceCapabilities";

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

describe("AV1 advertisement", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.mocked(isAvPlayAvailable).mockReturnValue(false);
  });

  it("advertises av1 when the platform probe says the panel decodes it", () => {
    // Without this the server always re-encodes AV1 sources to h264.
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: (codec) => codec === "AV1" },
        tizenVersion: 6.5,
      }),
    ).toBe(true);
  });

  it("accepts the alternate AV01 and AV1_VR360 spellings", () => {
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: (codec) => codec === "AV01" },
        tizenVersion: 6.0,
      }),
    ).toBe(true);
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: (codec) => codec === "AV1_VR360" },
        tizenVersion: 6.5,
        canPlayAv1: false,
      }),
    ).toBe(true);
  });

  it("does not let a negative systeminfo veto canPlayType on Tizen ≥ 5.5", () => {
    // 2022 QLEDs have denied "AV1" in systeminfo while still decoding av01.
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: () => false },
        tizenVersion: 6.5,
        canPlayAv1: true,
      }),
    ).toBe(true);
  });

  it("stays off when both systeminfo and canPlayType are negative", () => {
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: () => false },
        tizenVersion: 6.5,
        canPlayAv1: false,
      }),
    ).toBe(false);
  });

  it("refuses AV1 on panels older than Tizen 5.5", () => {
    expect(
      probeAv1Support({
        systemInfo: { isSupportedVideoCodec: () => true },
        tizenVersion: 5.0,
      }),
    ).toBe(false);
  });

  it("uses media capabilities when the probe is missing", () => {
    expect(probeAv1Support({ systemInfo: {}, tizenVersion: 6.5, canPlayAv1: true })).toBe(true);
    expect(probeAv1Support({ systemInfo: null, tizenVersion: 6.5, canPlayAv1: true })).toBe(true);
    expect(probeAv1Support({ systemInfo: null, tizenVersion: 6.5, canPlayAv1: false })).toBe(false);
  });

  it("stays out of the list off-device where the version is unknown", () => {
    expect(probeAv1Support({ systemInfo: null, tizenVersion: 0, canPlayAv1: true })).toBe(false);
  });

  it("survives probes that throw", () => {
    expect(
      probeAv1Support({
        systemInfo: {
          isSupportedVideoCodec: () => {
            throw new Error("not implemented");
          },
        },
        tizenVersion: 6.5,
        canPlayAv1: true,
      }),
    ).toBe(true);
  });

  it("includes av1 in the advertised codec list", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 3840, height: 2160 });
    stubWindow({ innerWidth: 1920, innerHeight: 1080 });
    const caps = probeTvPlaybackCapabilities({
      avplayAvailable: true,
      systemInfo: { isSupportedVideoCodec: (codec) => codec === "AV1" || codec === "HEVC" },
      tizenVersion: 6.5,
    });
    expect(caps.codecs_video).toEqual(["h264", "hevc", "av1"]);
  });

  it("keeps hevc from the version heuristic when the video probe is absent", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 1920, height: 1080 });
    stubWindow({ innerWidth: 1920, innerHeight: 1080 });
    const caps = probeTvPlaybackCapabilities({
      avplayAvailable: true,
      systemInfo: {},
      tizenVersion: 6.5,
      canPlayAv1: false,
    });
    expect(caps.codecs_video).toEqual(["h264", "hevc"]);
  });

  it("drops hevc when the platform probe denies it", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 1920, height: 1080 });
    stubWindow({ innerWidth: 1920, innerHeight: 1080 });
    const caps = probeTvPlaybackCapabilities({
      avplayAvailable: true,
      systemInfo: { isSupportedVideoCodec: () => false },
      tizenVersion: 6.5,
      canPlayAv1: false,
    });
    expect(caps.codecs_video).toEqual(["h264"]);
  });

  it("still advertises av1 when systeminfo denies but canPlayType affirms", () => {
    vi.stubGlobal("navigator", { userAgent: "Mozilla/5.0 (SMART-TV; Tizen 6.5)" });
    vi.stubGlobal("screen", { width: 3840, height: 2160 });
    stubWindow({ innerWidth: 1920, innerHeight: 1080 });
    const caps = probeTvPlaybackCapabilities({
      avplayAvailable: true,
      systemInfo: { isSupportedVideoCodec: (codec) => codec === "HEVC" },
      tizenVersion: 6.5,
      canPlayAv1: true,
    });
    expect(caps.codecs_video).toEqual(["h264", "hevc", "av1"]);
  });
});

describe("AV1 advertise overrides", () => {
  it("force-injects and strips av1 independently of the probe", () => {
    const base = {
      codecs_video: ["h264", "hevc"],
      codecs_audio: ["aac"],
      containers: ["mp4"],
      max_resolution: "1080p",
      hdr: false,
    };
    expect(applyAv1AdvertiseOverrides(base, { forceAv1: true }).codecs_video).toEqual([
      "h264",
      "hevc",
      "av1",
    ]);
    expect(
      applyAv1AdvertiseOverrides(
        { ...base, codecs_video: ["h264", "hevc", "av1"] },
        { disableAv1: true },
      ).codecs_video,
    ).toEqual(["h264", "hevc"]);
    expect(
      resolveAdvertisedCapabilities(
        { forceAv1: true },
        {
          avplayAvailable: false,
          systemInfo: { isSupportedVideoCodec: () => false },
          tizenVersion: 6.5,
          canPlayAv1: false,
        },
      ).codecs_video,
    ).toContain("av1");
  });
});

describe("tizenPlatformVersion", () => {
  it("parses major and minor versions", () => {
    expect(tizenPlatformVersion("Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.5)")).toBe(6.5);
    expect(tizenPlatformVersion("Mozilla/5.0 (SMART-TV; LINUX; Tizen 5.5)")).toBe(5.5);
    expect(tizenPlatformVersion("Tizen/4.0")).toBe(4);
    expect(tizenPlatformVersion("Mozilla/5.0 (Macintosh)")).toBe(0);
  });
});
