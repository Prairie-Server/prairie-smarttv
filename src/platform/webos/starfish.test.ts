import { describe, expect, it } from "vitest";
import {
  buildStarfishMediaOption,
  createStarfishPlayer,
  detectStarfishStreamKind,
  resolveStarfishMimeType,
} from "./starfish";

describe("detectStarfishStreamKind", () => {
  it("detects HLS from URL and MIME", () => {
    expect(detectStarfishStreamKind("https://x/master.m3u8")).toBe("hls");
    expect(
      detectStarfishStreamKind("https://x/stream?token=1", "application/vnd.apple.mpegurl"),
    ).toBe("hls");
    expect(
      detectStarfishStreamKind("https://x/api/v1/playback/transcode/s/master.m3u8?token=a"),
    ).toBe("hls");
  });

  it("detects progressive MP4", () => {
    expect(detectStarfishStreamKind("https://x/file.mp4")).toBe("mp4");
    expect(detectStarfishStreamKind("https://x/stream", "video/mp4")).toBe("mp4");
  });
});

describe("resolveStarfishMimeType", () => {
  it("uses MPEG-URL for HLS so webOS selects the HLS pipeline", () => {
    expect(resolveStarfishMimeType("https://x/a.m3u8")).toBe("application/vnd.apple.mpegurl");
  });

  it("defaults progressive to video/mp4", () => {
    expect(resolveStarfishMimeType("https://x/a.mp4")).toBe("video/mp4");
  });
});

describe("buildStarfishMediaOption", () => {
  it("sets HLS transport + adaptiveStreaming for native HLS", () => {
    const raw = buildStarfishMediaOption({ preferNative: true, kind: "hls" });
    expect(raw).toBeTruthy();
    const parsed = JSON.parse(raw!);
    expect(parsed.mediaTransportType).toBe("HLS");
    expect(parsed.option.adaptiveStreaming.seamlessPlay).toBe(true);
  });

  it("sets URI transport for progressive direct play", () => {
    const raw = buildStarfishMediaOption({ preferNative: true, kind: "mp4" });
    const parsed = JSON.parse(raw!);
    expect(parsed.mediaTransportType).toBe("URI");
  });

  it("returns undefined when native is disabled", () => {
    expect(buildStarfishMediaOption({ preferNative: false, kind: "hls" })).toBeUndefined();
  });
});

describe("createStarfishPlayer", () => {
  it("tags HLS sources with MPEG-URL mediaOption", () => {
    const container = document.createElement("div");
    const player = createStarfishPlayer({
      url: "https://prairie.example/api/v1/playback/transcode/s1/master.m3u8?token=tok",
      container,
      autoplay: false,
    });
    const source = container.querySelector("source");
    expect(source?.getAttribute("type")).toContain("application/vnd.apple.mpegurl");
    expect(source?.getAttribute("type")).toContain("mediaOption=");
    expect(decodeURIComponent(source!.getAttribute("type")!)).toContain(
      '"mediaTransportType":"HLS"',
    );
    expect(container.querySelector("video")?.getAttribute("mediaPreferred")).toBe("true");
    player.destroy();
  });

  it("tags progressive sources as video/mp4 URI", () => {
    const container = document.createElement("div");
    const player = createStarfishPlayer({
      url: "https://prairie.example/api/v1/stream/abc.mp4?token=tok",
      container,
      autoplay: false,
    });
    const source = container.querySelector("source");
    expect(source?.getAttribute("type")).toContain("video/mp4");
    expect(decodeURIComponent(source!.getAttribute("type")!)).toContain(
      '"mediaTransportType":"URI"',
    );
    player.destroy();
  });
});
