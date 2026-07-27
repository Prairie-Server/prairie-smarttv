import { describe, expect, it, vi } from "vitest";
import { isHlsUrl, waitForHlsManifest } from "./waitForHlsManifest";

describe("isHlsUrl", () => {
  it("detects m3u8 manifests", () => {
    expect(isHlsUrl("https://x/master.m3u8?token=1")).toBe(true);
    expect(isHlsUrl("https://x/api/v1/hls/playlist")).toBe(true);
    expect(isHlsUrl("https://x/api/v1/stream/abc.mp4")).toBe(false);
  });
});

describe("waitForHlsManifest", () => {
  it("resolves true once #EXTM3U appears", async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async () => {
      calls += 1;
      if (calls < 2) return new Response("not yet", { status: 404 });
      return new Response("#EXTM3U\n#EXT-X-STREAM-INF\n", { status: 200 });
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 2_000,
      }),
    ).resolves.toBe(true);
    expect(calls).toBeGreaterThanOrEqual(2);
  });

  it("uses default fetch and timing options when omitted", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("#EXTM3U\n", { status: 200 }),
    );
    await expect(waitForHlsManifest("https://x/b.m3u8", { timeoutMs: 500 })).resolves.toBe(true);
    expect(fetchSpy).toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("resolves false on timeout", async () => {
    const fetchImpl = vi.fn(async () => new Response("", { status: 404 }));
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 20,
      }),
    ).resolves.toBe(false);
  });

  it("treats fetch failures as empty until timeout", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error("network down");
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 20,
      }),
    ).resolves.toBe(false);
  });
});
