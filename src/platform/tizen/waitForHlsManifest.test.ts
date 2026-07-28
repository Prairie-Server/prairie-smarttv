import { describe, expect, it, vi } from "vitest";
import {
  firstMediaSegmentUrl,
  isHlsUrl,
  TranscodeStartupTimeoutError,
  waitForHlsManifest,
} from "./waitForHlsManifest";

describe("isHlsUrl", () => {
  it("detects m3u8 manifests", () => {
    expect(isHlsUrl("https://x/master.m3u8?token=1")).toBe(true);
    expect(isHlsUrl("https://x/api/v1/hls/playlist")).toBe(true);
    expect(isHlsUrl("https://x/api/v1/stream/abc.mp4")).toBe(false);
  });
});

describe("firstMediaSegmentUrl", () => {
  it("resolves relative segment URIs", () => {
    const body = "#EXTM3U\n#EXTINF:2.0,\nsegment/seg_00000.ts\n";
    expect(firstMediaSegmentUrl("https://x/master.m3u8?token=1", body)).toBe(
      "https://x/segment/seg_00000.ts?token=1",
    );
  });
  it("inherits the playlist query on relative segments", () => {
    expect(firstMediaSegmentUrl("https://x/a.m3u8?auth=1", "#EXTM3U\n#EXTINF:1,\nseg.ts\n")).toBe(
      "https://x/seg.ts?auth=1",
    );
  });
});

describe("waitForHlsManifest", () => {
  it("resolves true once the first segment is fetchable", async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const href = String(url);
      if (href.includes(".m3u8")) {
        calls += 1;
        if (calls < 2) return new Response("not yet", { status: 404 });
        return new Response("#EXTM3U\n#EXTINF:2.0,\nsegment/seg_00000.ts\n", { status: 200 });
      }
      if (init?.method === "HEAD" || href.includes("seg_00000")) {
        return new Response(null, { status: 200 });
      }
      return new Response("", { status: 404 });
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 2_000,
        requireSegment: true,
      }),
    ).resolves.toBe(true);
    expect(calls).toBeGreaterThanOrEqual(2);
  });

  it("treats #EXTM3U alone as ready when requireSegment is false", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response("#EXTM3U\n", { status: 200 }));
    await expect(
      waitForHlsManifest("https://x/b.m3u8", { timeoutMs: 500, requireSegment: false }),
    ).resolves.toBe(true);
    expect(fetchSpy).toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("resolves false on timeout when throwOnTimeout is false", async () => {
    const fetchImpl = vi.fn(async () => new Response("", { status: 404 }));
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 20,
        throwOnTimeout: false,
      }),
    ).resolves.toBe(false);
  });

  it("throws TranscodeStartupTimeoutError when throwOnTimeout is true", async () => {
    const fetchImpl = vi.fn(async () => new Response("", { status: 404 }));
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 20,
        throwOnTimeout: true,
      }),
    ).rejects.toBeInstanceOf(TranscodeStartupTimeoutError);
  });

  it("fires keepalive during the wait", async () => {
    const keepAlive = vi.fn(async () => undefined);
    let calls = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const href = String(url);
      if (href.includes(".m3u8")) {
        calls += 1;
        if (calls < 3) return new Response("", { status: 404 });
        return new Response("#EXTM3U\n#EXTINF:2.0,\nseg.ts\n", { status: 200 });
      }
      if (init?.method === "HEAD" || href.endsWith("seg.ts")) {
        return new Response(null, { status: 200 });
      }
      return new Response("", { status: 404 });
    });
    await waitForHlsManifest("https://x/a.m3u8", {
      fetchImpl: fetchImpl as unknown as typeof fetch,
      intervalMs: 1,
      timeoutMs: 2_000,
      keepAliveEveryMs: 1,
      onKeepAlive: keepAlive,
    });
    expect(keepAlive).toHaveBeenCalled();
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
        throwOnTimeout: false,
      }),
    ).resolves.toBe(false);
  });

  it("falls back from HEAD to a ranged GET when HEAD is unsupported", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const href = String(url);
      if (href.includes(".m3u8")) {
        return new Response("#EXTM3U\n#EXTINF:2.0,\nseg.ts\n", { status: 200 });
      }
      if (init?.method === "HEAD") return new Response(null, { status: 405 });
      if (init?.method === "GET") return new Response(null, { status: 206 });
      return new Response("", { status: 404 });
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8?token=1", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 500,
      }),
    ).resolves.toBe(true);
  });

  it("ignores keepalive failures and keeps polling", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      if (String(url).includes(".m3u8")) {
        return new Response("#EXTM3U\n", { status: 200 });
      }
      return new Response("", { status: 404 });
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 20,
        requireSegment: false,
        keepAliveEveryMs: 1,
        onKeepAlive: () => {
          throw new Error("keepalive down");
        },
      }),
    ).resolves.toBe(true);
  });

  it("keeps polling when the playlist has no media segments yet", async () => {
    let calls = 0;
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const href = String(url);
      if (href.includes(".m3u8")) {
        calls += 1;
        if (calls < 2) return new Response("#EXTM3U\n", { status: 200 });
        return new Response("#EXTM3U\n#EXTINF:2.0,\nseg.ts\n", { status: 200 });
      }
      if (init?.method === "HEAD" || href.endsWith("seg.ts")) {
        return new Response(null, { status: 200 });
      }
      return new Response("", { status: 404 });
    });
    await expect(
      waitForHlsManifest("https://x/a.m3u8", {
        fetchImpl: fetchImpl as unknown as typeof fetch,
        intervalMs: 1,
        timeoutMs: 500,
      }),
    ).resolves.toBe(true);
    expect(calls).toBeGreaterThanOrEqual(2);
  });
});
