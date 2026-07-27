import { describe, expect, it } from "vitest";
import { isHlsSource, resolveHtml5Source, TV_HLS_CONFIG } from "./hlsSource";

describe("isHlsSource", () => {
  it("detects manifests by extension, ignoring query and fragment", () => {
    expect(isHlsSource("https://tv.example/transcode/abc/index.m3u8")).toBe(true);
    expect(isHlsSource("https://tv.example/transcode/abc/index.m3u8?token=x")).toBe(true);
    expect(isHlsSource("https://tv.example/transcode/abc/index.M3U8#t=10")).toBe(true);
    expect(isHlsSource("https://tv.example/stream/abc.mp4")).toBe(false);
  });

  it("detects manifests by MIME type", () => {
    expect(isHlsSource("https://tv.example/stream", "application/vnd.apple.mpegurl")).toBe(true);
    expect(isHlsSource("https://tv.example/stream", "application/x-mpegURL")).toBe(true);
    expect(isHlsSource("https://tv.example/stream", "video/mp4")).toBe(false);
  });
});

describe("resolveHtml5Source", () => {
  const manifest = "https://tv.example/transcode/abc/index.m3u8";

  it("prefers native HLS when the WebView claims support", () => {
    expect(
      resolveHtml5Source({ url: manifest, nativeHlsSupport: "probably", hlsJsSupported: true }),
    ).toBe("native-hls");
    expect(resolveHtml5Source({ url: manifest, nativeHlsSupport: "maybe" })).toBe("native-hls");
  });

  it("uses hls.js when there is no native HLS but MSE is available", () => {
    // This is Tizen: Chromium 85 reports "" for the HLS MIME type.
    expect(resolveHtml5Source({ url: manifest, nativeHlsSupport: "", hlsJsSupported: true })).toBe(
      "hls-js",
    );
  });

  it("falls back to a direct src when neither is available", () => {
    // Nothing can play it, but the media element surfaces an error rather than
    // hanging with a manifest that is never fetched.
    expect(resolveHtml5Source({ url: manifest, nativeHlsSupport: "", hlsJsSupported: false })).toBe(
      "progressive",
    );
  });

  it("leaves progressive MP4 alone", () => {
    expect(
      resolveHtml5Source({
        url: "https://tv.example/stream/abc.mp4",
        mimeType: "video/mp4",
        hlsJsSupported: true,
      }),
    ).toBe("progressive");
  });
});

describe("TV_HLS_CONFIG", () => {
  it("disables workers and caps buffers for TV memory", () => {
    expect(TV_HLS_CONFIG.enableWorker).toBe(false);
    expect(TV_HLS_CONFIG.lowLatencyMode).toBe(false);
    expect(TV_HLS_CONFIG.maxBufferLength).toBeLessThanOrEqual(30);
    expect(TV_HLS_CONFIG.maxMaxBufferLength).toBeLessThanOrEqual(60);
    expect(TV_HLS_CONFIG.backBufferLength).toBeLessThanOrEqual(30);
  });
});
