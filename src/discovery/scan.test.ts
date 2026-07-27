import { describe, expect, it, vi } from "vitest";
import { runLanDiscovery } from "./scan";

describe("runLanDiscovery", () => {
  it("returns health hits from parallel probes and reports progress", async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("192.168.1.10:8080")) {
        return new Response(
          JSON.stringify({ status: "ok", server_name: "Home", server_id: "h1" }),
          { status: 200 },
        );
      }
      return new Response("nope", { status: 404 });
    }) as unknown as typeof fetch;

    const progress: Array<[number, number]> = [];
    const hits = await runLanDiscovery({
      extraCidrs: ["192.168.1.0/24"],
      deepScan: false,
      maxHostsPerCidr: 8,
      concurrency: 8,
      timeoutMs: 200,
      localIps: [],
      fetchImpl,
      onProgress: (done, total) => progress.push([done, total]),
    });

    expect(hits).toEqual([{ url: "http://192.168.1.10:8080", serverName: "Home", serverId: "h1" }]);
    expect(progress.length).toBeGreaterThan(0);
    expect(progress.at(-1)?.[0]).toBe(progress.at(-1)?.[1]);
  });

  it("stops when aborted", async () => {
    const controller = new AbortController();
    let calls = 0;
    const fetchImpl = vi.fn(async () => {
      calls += 1;
      if (calls === 2) controller.abort();
      await new Promise((r) => setTimeout(r, 30));
      return new Response(JSON.stringify({ status: "ok" }), { status: 200 });
    }) as unknown as typeof fetch;

    await runLanDiscovery({
      extraCidrs: ["192.168.1.0/24"],
      deepScan: true,
      maxHostsPerCidr: 40,
      concurrency: 2,
      timeoutMs: 200,
      localIps: [],
      signal: controller.signal,
      fetchImpl,
    });

    expect(calls).toBeLessThan(40);
  });

  it("skips probes when the signal is already aborted", async () => {
    const controller = new AbortController();
    controller.abort();
    const fetchImpl = vi.fn(
      async () => new Response("{}", { status: 200 }),
    ) as unknown as typeof fetch;
    const hits = await runLanDiscovery({
      extraCidrs: ["192.168.1.0/24"],
      deepScan: false,
      maxHostsPerCidr: 4,
      concurrency: 2,
      timeoutMs: 50,
      localIps: [],
      signal: controller.signal,
      fetchImpl,
      onHit: () => undefined,
    });
    expect(hits).toEqual([]);
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it("ignores failed and unhealthy probes without reporting hits", async () => {
    const onHit = vi.fn();
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("192.168.1.1:8080")) {
        throw new Error("network down");
      }
      return new Response(JSON.stringify({ status: "down" }), { status: 200 });
    }) as unknown as typeof fetch;

    const hits = await runLanDiscovery({
      extraCidrs: ["192.168.1.0/24"],
      deepScan: false,
      maxHostsPerCidr: 1,
      concurrency: 1,
      timeoutMs: 50,
      localIps: [],
      fetchImpl,
      onHit,
    });

    expect(hits).toEqual([]);
    expect(onHit).not.toHaveBeenCalled();
    expect(fetchImpl).toHaveBeenCalled();
  });

  it("forwards configured baseHosts into candidate probing", async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("prairie.lan")) {
        return new Response(JSON.stringify({ status: "ok", server_name: "Lan", server_id: "l1" }), {
          status: 200,
        });
      }
      return new Response("nope", { status: 404 });
    }) as unknown as typeof fetch;

    const hits = await runLanDiscovery({
      extraCidrs: [],
      deepScan: false,
      maxHostsPerCidr: 1,
      concurrency: 4,
      timeoutMs: 100,
      localIps: [],
      baseHosts: ["prairie.lan"],
      fetchImpl,
    });

    expect(hits.some((hit) => hit.url.includes("prairie.lan"))).toBe(true);
    expect(fetchImpl.mock.calls.some((call) => String(call[0]).includes("prairie.lan"))).toBe(true);
  });

  it("falls back to platform local IPs when localIps is omitted", async () => {
    const fetchImpl = vi.fn(
      async () => new Response(JSON.stringify({ status: "down" }), { status: 200 }),
    ) as unknown as typeof fetch;

    const hits = await runLanDiscovery({
      extraCidrs: [],
      deepScan: false,
      maxHostsPerCidr: 1,
      concurrency: 2,
      timeoutMs: 50,
      baseHosts: ["prairie.lan"],
      fetchImpl,
    });

    expect(hits).toEqual([]);
    expect(fetchImpl).toHaveBeenCalled();
  });
});
