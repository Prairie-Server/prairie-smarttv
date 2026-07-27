import { afterEach, describe, expect, it, vi } from "vitest";
import {
  COMMON_CIDRS,
  DEEP_SCAN_PORTS,
  HEALTH_PATH,
  allHostsForCidr,
  buildCandidates,
  localIpv4Addresses,
  mergeHits,
  parseCidr,
  parseHealth,
  priorityHostsForSubnet,
  subnetCidrForIp,
} from "./discover";

describe("discover", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("parses ok health payloads and rejects down servers", () => {
    expect(parseHealth({ status: "ok", server_name: "Prairie Home", server_id: "abc" })).toEqual({
      serverName: "Prairie Home",
      serverId: "abc",
    });
    expect(parseHealth({ status: "healthy" })).toEqual({ serverName: "", serverId: "" });
    expect(parseHealth({ status: "down" })).toBeNull();
    expect(parseHealth(null)).toBeNull();
    expect(HEALTH_PATH).toBe("/api/v1/health");
    expect(DEEP_SCAN_PORTS[0]).toBe(8080);
  });

  it("includes Litefin-style common /24s and priority hosts for Prairie ports", () => {
    expect(parseCidr("192.168.1.0/24")?.prefix).toBe(24);
    expect(parseCidr("10.0.0.0/16")).toBeNull();
    expect(subnetCidrForIp("192.168.1.50")).toBe("192.168.1.0/24");
    const hosts = priorityHostsForSubnet([192, 168, 1, 0]);
    expect(hosts[0]).toBe("192.168.1.1");
    expect(COMMON_CIDRS[0]).toBe("192.168.0.0/24");

    const candidates = buildCandidates({
      extraCidrs: ["192.168.2.0/24"],
      deepScan: false,
      maxHostsPerCidr: 16,
    });
    const joined = candidates.join(",");
    expect(joined).toContain("prairie.local");
    expect(joined).toContain("192.168.2.1");
    expect(joined).toContain("192.168.0.1");
    expect(joined).toContain("192.168.1.1");
    expect(joined).toContain("10.0.0.1");
    expect(joined).toContain(":8080");
    expect(joined).not.toContain("/System/Info");
  });

  it("expands a /24 on the Prairie listen port only for deep scan", () => {
    const deep = buildCandidates({
      extraCidrs: ["192.168.9.0/24"],
      deepScan: true,
      maxHostsPerCidr: 12,
    });
    const joined = deep.join(",");
    expect(joined).toContain("192.168.9.1:8080");
    expect(joined).toContain("192.168.9.12:8080");
    expect(joined).not.toContain("https://192.168.9.1:8080");
    expect(allHostsForCidr({ network: [192, 168, 9, 0], prefix: 24 }, 3)).toHaveLength(3);
  });

  it("dedupes discovered servers by normalized URL", () => {
    let hits = mergeHits([], "https://prairie.example.com/", {
      serverName: "One",
      serverId: "1",
    });
    hits = mergeHits(hits, "https://prairie.example.com", {
      serverName: "Two",
      serverId: "1",
    });
    expect(hits).toHaveLength(1);
    expect(hits[0]?.serverName).toBe("Two");
    hits = mergeHits(hits, "https://prairie.example.com", {
      serverName: "",
      serverId: "",
    });
    expect(hits[0]?.serverName).toBe("Two");
  });

  it("probes local device IP when provided", () => {
    const candidates = buildCandidates({
      localIps: ["10.0.0.42"],
      deepScan: false,
      maxHostsPerCidr: 4,
      extraCidrs: [],
    });
    expect(candidates.some((url) => url.includes("10.0.0.42"))).toBe(true);
  });

  it("reads local IPv4 from webapis when available", () => {
    vi.stubGlobal("window", {
      webapis: {
        network: {
          getIp: () => "192.168.1.20",
        },
      },
    });
    expect(localIpv4Addresses()).toEqual(["192.168.1.20"]);

    vi.stubGlobal("window", {
      webapis: {
        network: {
          getIp: () => {
            throw new Error("denied");
          },
        },
      },
    });
    expect(localIpv4Addresses()).toEqual([]);
  });
});
