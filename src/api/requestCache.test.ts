import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ApiClientOptions } from "./client";

const apiRequest = vi.fn();

vi.mock("./client", () => ({
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));

const {
  CACHE_TTL_MS,
  cachedRequest,
  invalidateAll,
  invalidateItem,
  invalidateWatchState,
  invalidateWhere,
  requestCacheStats,
  resetRequestCacheForTests,
} = await import("./requestCache");

const options: ApiClientOptions = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  profileId: "p1",
};

/** Same server, different viewer — must not share entries. */
const otherProfile: ApiClientOptions = { ...options, profileId: "p2" };
/** Different server entirely. */
const otherServer: ApiClientOptions = { ...options, serverUrl: "https://other.example.com" };

/** Never settles until `resolve` is called, so in-flight state is observable. */
function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (err: unknown) => void;
} {
  let resolve!: (value: T) => void;
  let reject!: (err: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-01-01T00:00:00Z"));
  resetRequestCacheForTests();
  apiRequest.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("cachedRequest", () => {
  it("serves a second read from cache without touching the network", async () => {
    apiRequest.mockResolvedValue({ title: "A" });

    const first = await cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);
    const second = await cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);

    expect(first).toEqual({ title: "A" });
    expect(second).toBe(first);
    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("re-fetches once the entry has expired", async () => {
    apiRequest.mockResolvedValueOnce({ n: 1 }).mockResolvedValueOnce({ n: 2 });

    await cachedRequest(options, "/p", 1000);
    vi.setSystemTime(Date.now() + 1001);
    const again = await cachedRequest(options, "/p", 1000);

    expect(again).toEqual({ n: 2 });
    expect(apiRequest).toHaveBeenCalledTimes(2);
  });

  it("treats an entry as live right up to its expiry", async () => {
    apiRequest.mockResolvedValue({ n: 1 });

    await cachedRequest(options, "/p", 1000);
    vi.setSystemTime(Date.now() + 999);
    await cachedRequest(options, "/p", 1000);

    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("joins callers that arrive while a request is in flight", async () => {
    const gate = deferred<{ n: number }>();
    apiRequest.mockReturnValue(gate.promise);

    const a = cachedRequest(options, "/livetv/channels", 60_000);
    const b = cachedRequest(options, "/livetv/channels", 60_000);
    expect(requestCacheStats().inFlight).toBe(1);

    gate.resolve({ n: 7 });
    expect(await a).toEqual({ n: 7 });
    expect(await b).toEqual({ n: 7 });
    expect(apiRequest).toHaveBeenCalledTimes(1);
    expect(requestCacheStats()).toEqual({ entries: 1, inFlight: 0 });
  });

  it("does not cache a rejection, and releases the in-flight slot", async () => {
    apiRequest.mockRejectedValueOnce(new Error("boom")).mockResolvedValueOnce({ ok: true });

    await expect(cachedRequest(options, "/p", 60_000)).rejects.toThrow("boom");
    expect(requestCacheStats()).toEqual({ entries: 0, inFlight: 0 });

    await expect(cachedRequest(options, "/p", 60_000)).resolves.toEqual({ ok: true });
    expect(apiRequest).toHaveBeenCalledTimes(2);
  });

  it("propagates a rejection to every joined caller", async () => {
    const gate = deferred<unknown>();
    apiRequest.mockReturnValue(gate.promise);

    const a = cachedRequest(options, "/p", 60_000);
    const b = cachedRequest(options, "/p", 60_000);
    gate.reject(new Error("down"));

    await expect(a).rejects.toThrow("down");
    await expect(b).rejects.toThrow("down");
    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("bypasses the cache when the caller supplies its own fetch", async () => {
    apiRequest.mockResolvedValue({ n: 1 });
    const withFetch: ApiClientOptions = {
      ...options,
      fetchImpl: (async () => new Response()) as typeof fetch,
    };

    await cachedRequest(withFetch, "/p", 60_000);
    await cachedRequest(withFetch, "/p", 60_000);

    expect(apiRequest).toHaveBeenCalledTimes(2);
    expect(requestCacheStats()).toEqual({ entries: 0, inFlight: 0 });
  });

  it("keys entries by profile and by server", async () => {
    apiRequest.mockResolvedValue({});

    await cachedRequest(options, "/p", 60_000);
    await cachedRequest(otherProfile, "/p", 60_000);
    await cachedRequest(otherServer, "/p", 60_000);

    expect(apiRequest).toHaveBeenCalledTimes(3);
    expect(requestCacheStats().entries).toBe(3);
  });

  it("treats an absent profile as its own scope", async () => {
    apiRequest.mockResolvedValue({});
    const anonymous: ApiClientOptions = { serverUrl: options.serverUrl };

    await cachedRequest(anonymous, "/p", 60_000);
    await cachedRequest(anonymous, "/p", 60_000);

    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("evicts oldest entries past the bound rather than growing without limit", async () => {
    apiRequest.mockResolvedValue({});
    for (let i = 0; i < 130; i++) {
      await cachedRequest(options, `/p/${i}`, 60_000);
    }

    expect(requestCacheStats().entries).toBe(120);
    // The earliest paths were evicted; the most recent survive.
    apiRequest.mockClear();
    await cachedRequest(options, "/p/0", 60_000);
    expect(apiRequest).toHaveBeenCalledTimes(1);
    apiRequest.mockClear();
    await cachedRequest(options, "/p/129", 60_000);
    expect(apiRequest).not.toHaveBeenCalled();
  });

  it("exposes per-endpoint TTLs that keep watch-derived reads shortest", () => {
    expect(CACHE_TTL_MS.homeSections).toBeLessThan(CACHE_TTL_MS.seasons);
    expect(CACHE_TTL_MS.itemDetail).toBeLessThan(CACHE_TTL_MS.similar);
  });
});

describe("invalidation", () => {
  it("drops matching entries and leaves the rest", async () => {
    apiRequest.mockResolvedValue({});
    await cachedRequest(options, "/api/v1/keep", 60_000);
    await cachedRequest(options, "/api/v1/drop", 60_000);

    invalidateWhere((path) => path.includes("drop"));

    apiRequest.mockClear();
    await cachedRequest(options, "/api/v1/keep", 60_000);
    expect(apiRequest).not.toHaveBeenCalled();
    await cachedRequest(options, "/api/v1/drop", 60_000);
    expect(apiRequest).toHaveBeenCalledTimes(1);
  });

  it("detaches an in-flight request so its late response is not stored", async () => {
    const gate = deferred<{ stale: boolean }>();
    apiRequest.mockReturnValue(gate.promise);

    const pending = cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);
    // A write lands while the read is still on the wire.
    invalidateItem("m1");
    gate.resolve({ stale: true });
    await pending;

    // The caller still gets its answer, but nothing pre-write was retained.
    apiRequest.mockResolvedValue({ stale: false });
    const next = await cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);
    expect(next).toEqual({ stale: false });
  });

  it("invalidateItem clears the item, its browse grids and Home", async () => {
    apiRequest.mockResolvedValue({});
    await cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);
    await cachedRequest(options, "/api/v1/catalog/items/m2", 60_000);
    await cachedRequest(options, "/api/v1/catalog?library_id=1", 60_000);
    await cachedRequest(options, "/api/v1/home/sections", 60_000);
    await cachedRequest(options, "/api/v1/user/libraries", 60_000);

    invalidateItem("m1");

    expect(requestCacheStats().entries).toBe(2);
    apiRequest.mockClear();
    // Untouched: another item's detail and the library list.
    await cachedRequest(options, "/api/v1/catalog/items/m2", 60_000);
    await cachedRequest(options, "/api/v1/user/libraries", 60_000);
    expect(apiRequest).not.toHaveBeenCalled();
  });

  it("invalidateItem encodes ids that need it", async () => {
    apiRequest.mockResolvedValue({});
    const path = `/api/v1/catalog/items/${encodeURIComponent("tt/1 2")}`;
    await cachedRequest(options, path, 60_000);

    invalidateItem("tt/1 2");

    expect(requestCacheStats().entries).toBe(0);
  });

  it("invalidateWatchState clears progress-derived reads only", async () => {
    apiRequest.mockResolvedValue({});
    await cachedRequest(options, "/api/v1/home/sections", 60_000);
    await cachedRequest(options, "/api/v1/catalog?library_id=1", 60_000);
    await cachedRequest(options, "/api/v1/user/libraries", 60_000);

    invalidateWatchState();

    expect(requestCacheStats().entries).toBe(1);
    apiRequest.mockClear();
    await cachedRequest(options, "/api/v1/user/libraries", 60_000);
    expect(apiRequest).not.toHaveBeenCalled();
  });

  it("leaves unrelated in-flight requests attached", async () => {
    const keep = deferred<{ n: number }>();
    const drop = deferred<{ n: number }>();
    apiRequest.mockReturnValueOnce(keep.promise).mockReturnValueOnce(drop.promise);

    const keepPending = cachedRequest(options, "/api/v1/keep", 60_000);
    const dropPending = cachedRequest(options, "/api/v1/drop", 60_000);
    invalidateWhere((path) => path.includes("drop"));

    keep.resolve({ n: 1 });
    drop.resolve({ n: 2 });
    await Promise.all([keepPending, dropPending]);

    // The untouched request still became an entry; the invalidated one did not.
    expect(requestCacheStats().entries).toBe(1);
    apiRequest.mockClear();
    apiRequest.mockResolvedValue({});
    await cachedRequest(options, "/api/v1/keep", 60_000);
    expect(apiRequest).not.toHaveBeenCalled();
  });

  it("tolerates a request that is invalidated and then fails", async () => {
    const gate = deferred<unknown>();
    apiRequest.mockReturnValue(gate.promise);

    const pending = cachedRequest(options, "/api/v1/catalog/items/m1", 60_000);
    invalidateItem("m1");
    gate.reject(new Error("down"));

    await expect(pending).rejects.toThrow("down");
    expect(requestCacheStats()).toEqual({ entries: 0, inFlight: 0 });
  });

  it("invalidateAll forgets every scope", async () => {
    apiRequest.mockResolvedValue({});
    await cachedRequest(options, "/p", 60_000);
    await cachedRequest(otherServer, "/p", 60_000);

    invalidateAll();

    expect(requestCacheStats()).toEqual({ entries: 0, inFlight: 0 });
  });
});
