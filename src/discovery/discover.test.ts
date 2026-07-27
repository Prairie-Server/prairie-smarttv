import { afterEach, describe, expect, it, vi } from "vitest";
import {
  COMMON_CIDRS,
  DEEP_SCAN_PORTS,
  HEALTH_PATH,
  allHostsForCidr,
  buildCandidates,
  collectScanCidrs,
  formatIpv4,
  ipv4Parts,
  localIpv4Addresses,
  mergeHits,
  parseCidr,
  parseHealth,
  priorityHostsForSubnet,
  subnetCidrForIp,
  urlsForHost,
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
    expect(parseHealth({ status: "UP" })).toEqual({ serverName: "", serverId: "" });
    expect(parseHealth({ status: 1 })).toBeNull();
    expect(parseHealth({ status: "down" })).toBeNull();
    expect(parseHealth(null)).toBeNull();
    expect(HEALTH_PATH).toBe("/api/v1/health");
    expect(DEEP_SCAN_PORTS[0]).toBe(8080);
  });

  it("probes configured baseHosts instead of only prairie.local defaults", () => {
    const custom = buildCandidates({
      baseHosts: ["prairie.lan"],
      deepScan: false,
      maxHostsPerCidr: 4,
      extraCidrs: [],
      localIps: [],
    });
    expect(custom.some((url) => url.includes("prairie.lan"))).toBe(true);
    expect(custom.some((url) => url.includes("prairie.local"))).toBe(false);

    const emptyOverride = buildCandidates({
      baseHosts: [],
      deepScan: false,
      maxHostsPerCidr: 4,
      extraCidrs: [],
      localIps: [],
    });
    expect(emptyOverride.some((url) => url.includes("prairie.local"))).toBe(true);
  });

  it("includes Litefin-style common /24s and priority hosts for Prairie ports", () => {
    expect(parseCidr("192.168.1.0/24")?.prefix).toBe(24);
    expect(parseCidr("10.0.0.0/16")).toBeNull();
    expect(parseCidr("10.0.0.0")).toBeNull();
    expect(parseCidr("10.0.0.0/nope")).toBeNull();
    expect(parseCidr("10.0.0.999/24")).toBeNull();
    expect(ipv4Parts("10.0.0")).toBeNull();
    expect(ipv4Parts("10..0.1")).toBeNull();
    expect(ipv4Parts("10.0.x.1")).toBeNull();
    expect(formatIpv4([10, 0, 0, 1])).toBe("10.0.0.1");
    expect(subnetCidrForIp("192.168.1.50")).toBe("192.168.1.0/24");
    expect(subnetCidrForIp("not-an-ip")).toBe("");
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

  it("dedupes URL candidates and scan CIDRs case-insensitively", () => {
    const seen = new Set<string>();
    const urls: string[] = [];
    urlsForHost("prairie.local", [443, 80, 8443, 8080, 8080], seen, urls);
    expect(urls).toContain("https://prairie.local");
    expect(urls).toContain("http://prairie.local");
    expect(urls).toContain("https://prairie.local:8443");
    expect(urls.filter((url) => url === "http://prairie.local:8080")).toHaveLength(1);

    expect(
      collectScanCidrs([" 10.0.0.0/24 ", "", "192.168.1.0/24"], ["192.168.1.20", "bad"]),
    ).toEqual(["192.168.1.0/24", ...COMMON_CIDRS.filter((cidr) => cidr !== "192.168.1.0/24")]);
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
    expect(allHostsForCidr({ network: [192, 168, 9, 42], prefix: 32 }, 10)).toEqual([
      "192.168.9.42",
    ]);
    expect(allHostsForCidr({ network: [192, 168, 9, 0], prefix: 31 }, 10)).toEqual([
      "192.168.9.0",
      "192.168.9.1",
    ]);
    expect(allHostsForCidr({ network: [192, 168, 9, 250], prefix: 24 }, 20)).toEqual([
      "192.168.9.251",
      "192.168.9.252",
      "192.168.9.253",
      "192.168.9.254",
      "192.168.9.255",
    ]);
    expect(allHostsForCidr({ network: [192, 168, 9, 0], prefix: 23 }, 10)).toEqual([]);
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
      localIps: ["10.0.0.42", "not-an-ip"],
      deepScan: false,
      maxHostsPerCidr: 4,
      extraCidrs: ["bad-cidr"],
    });
    expect(candidates.some((url) => url.includes("10.0.0.42"))).toBe(true);
    expect(candidates.some((url) => url.includes("not-an-ip"))).toBe(false);
  });

  it("returns no local IPv4s when browser globals are unavailable", () => {
    vi.stubGlobal("window", undefined);
    expect(localIpv4Addresses()).toEqual([]);
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
