import { normalizeServerUrl } from "../storage/persist";

/** Native Prairie liveness + identity (not Jellyfin /System/Info/Public). */
export const HEALTH_PATH = "/api/v1/health";

/** Prairie default listen is :8080. Extra ports cover reverse-proxy / TLS setups. */
export const DEFAULT_PORTS = [8080, 8443, 443, 80] as const;

/** Deep LAN sweeps use a single port so a /24 finishes in reasonable time. */
export const DEEP_SCAN_PORTS = [8080] as const;

/** Same fallback prefixes Litefin uses when the NIC /24 is unknown or empty. */
export const COMMON_CIDRS = ["192.168.0.0/24", "192.168.1.0/24", "10.0.0.0/24"] as const;

const PRIORITY_LAST_OCTETS = [1, 2, 10, 20, 50, 100, 150, 200, 254] as const;

export interface HealthIdentity {
  serverName: string;
  serverId: string;
}

export interface DiscoveryHit {
  url: string;
  serverName: string;
  serverId: string;
}

export interface BuildCandidatesOptions {
  extraCidrs?: string[];
  deepScan?: boolean;
  maxHostsPerCidr?: number;
  /**
   * Hostnames to probe for cross-subnet discovery (resolved via unicast DNS A records).
   * If omitted, the legacy hardcoded defaults are used.
   */
  baseHosts?: readonly string[];
  /** Device IPv4s when the platform can expose them (often empty on Tizen/webOS). */
  localIps?: string[];
}

export function parseHealth(data: unknown): HealthIdentity | null {
  if (!data || typeof data !== "object") return null;
  const record = data as Record<string, unknown>;
  const status = typeof record.status === "string" ? record.status.toLowerCase() : "";
  if (status !== "ok" && status !== "healthy" && status !== "up") return null;
  return {
    serverName: typeof record.server_name === "string" ? record.server_name : "",
    serverId: typeof record.server_id === "string" ? record.server_id : "",
  };
}

export function ipv4Parts(ip: string): number[] | null {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  const nums: number[] = [];
  for (const part of parts) {
    if (!part.length || !/^\d+$/.test(part)) return null;
    const value = Number.parseInt(part, 10);
    if (!Number.isFinite(value) || value < 0 || value > 255) return null;
    nums.push(value);
  }
  return nums;
}

export function formatIpv4(parts: number[]): string {
  return `${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}`;
}

export function parseCidr(cidr: string): { network: number[]; prefix: number } | null {
  const trimmed = cidr.trim();
  const slash = trimmed.indexOf("/");
  if (slash < 0) return null;
  const ip = trimmed.slice(0, slash);
  const prefix = Number.parseInt(trimmed.slice(slash + 1), 10);
  if (!Number.isFinite(prefix) || prefix < 24 || prefix > 32) return null;
  const parts = ipv4Parts(ip);
  if (!parts) return null;
  return { network: parts, prefix };
}

export function subnetCidrForIp(ip: string): string {
  const parts = ipv4Parts(ip);
  if (!parts) return "";
  return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
}

function pushUnique(list: string[], seen: Set<string>, value: string): void {
  const key = value.toLowerCase();
  if (seen.has(key)) return;
  seen.add(key);
  list.push(value);
}

export function urlsForHost(
  host: string,
  ports: readonly number[],
  seen: Set<string>,
  out: string[],
): void {
  for (const port of ports) {
    if (port === 443) {
      pushUnique(out, seen, `https://${host}`);
    } else if (port === 80) {
      pushUnique(out, seen, `http://${host}`);
    } else {
      pushUnique(out, seen, `http://${host}:${port}`);
      if (port === 8443) {
        pushUnique(out, seen, `https://${host}:${port}`);
      }
    }
  }
}

export function priorityHostsForSubnet(base: number[]): string[] {
  return PRIORITY_LAST_OCTETS.map((last) => formatIpv4([base[0]!, base[1]!, base[2]!, last]));
}

export function allHostsForCidr(
  parsed: { network: number[]; prefix: number },
  maxHosts = 254,
): string[] {
  const hosts: string[] = [];
  const bits = 32 - parsed.prefix;
  if (bits === 0) {
    hosts.push(formatIpv4(parsed.network));
    return hosts;
  }
  const count = 2 ** bits;
  let startOffset = 1;
  let endOffset = count - 2;
  if (endOffset < startOffset) {
    startOffset = 0;
    endOffset = count - 1;
  }
  let added = 0;
  for (let offset = startOffset; offset <= endOffset; offset += 1) {
    if (added >= maxHosts) break;
    if (parsed.prefix < 24) break;
    const last = parsed.network[3]! + offset;
    if (last > 255) break;
    hosts.push(formatIpv4([parsed.network[0]!, parsed.network[1]!, parsed.network[2]!, last]));
    added += 1;
  }
  return hosts;
}

export function collectScanCidrs(extraCidrs: string[] = [], localIps: string[] = []): string[] {
  const cidrs: string[] = [];
  const seen = new Set<string>();
  for (const ip of localIps) {
    const cidr = subnetCidrForIp(ip);
    if (cidr) pushUnique(cidrs, seen, cidr);
  }
  for (const cidr of COMMON_CIDRS) {
    pushUnique(cidrs, seen, cidr);
  }
  for (const cidr of extraCidrs) {
    const trimmed = cidr.trim();
    if (trimmed) pushUnique(cidrs, seen, trimmed);
  }
  return cidrs;
}

/**
 * Build probe URLs (Litefin-shaped, Prairie-native):
 *   1) prairie.local / prairie
 *   2) local NIC /24 + common 192.168.0/1 + 10.0.0 (+ optional extras)
 *   3) deepScan=false → priority hosts on defaultPorts
 *      deepScan=true  → full /24 on deepScanPorts (:8080)
 */
export function buildCandidates(options: BuildCandidatesOptions = {}): string[] {
  const {
    extraCidrs = [],
    deepScan = false,
    maxHostsPerCidr = 254,
    localIps = [],
    baseHosts,
  } = options;
  const out: string[] = [];
  const seen = new Set<string>();

  const defaultBaseHosts = ["prairie.local", "prairie"] as const;
  const hostsToProbe = baseHosts && baseHosts.length > 0 ? baseHosts : defaultBaseHosts;

  for (const host of hostsToProbe) {
    urlsForHost(host, DEFAULT_PORTS, seen, out);
  }
  for (const ip of localIps) {
    if (ipv4Parts(ip)) urlsForHost(ip, DEFAULT_PORTS, seen, out);
  }

  const cidrs = collectScanCidrs(extraCidrs, localIps);
  const hostPorts = deepScan ? DEEP_SCAN_PORTS : DEFAULT_PORTS;

  for (const cidr of cidrs) {
    const parsed = parseCidr(cidr);
    if (!parsed) continue;
    const hosts = deepScan
      ? allHostsForCidr(parsed, maxHostsPerCidr)
      : priorityHostsForSubnet(parsed.network);
    for (const host of hosts) {
      urlsForHost(host, hostPorts, seen, out);
    }
  }

  return out;
}

export function mergeHits(
  hits: DiscoveryHit[],
  url: string,
  health: HealthIdentity,
): DiscoveryHit[] {
  const normalized = normalizeServerUrl(url);
  const existing = hits.find((hit) => hit.url === normalized);
  if (existing) {
    if (health.serverName) existing.serverName = health.serverName;
    if (health.serverId) existing.serverId = health.serverId;
    return hits;
  }
  hits.push({
    url: normalized,
    serverName: health.serverName,
    serverId: health.serverId,
  });
  return hits;
}

/**
 * Best-effort local IPv4 discovery. Tizen/webOS web apps often cannot read the
 * NIC address; callers then fall back to COMMON_CIDRS only.
 */
export function localIpv4Addresses(): string[] {
  if (typeof window === "undefined") return [];
  const ips: string[] = [];
  const seen = new Set<string>();

  // Some Tizen builds expose network interfaces on webapis.
  try {
    const network = (
      window as unknown as {
        webapis?: { network?: { getIp?: () => string } };
      }
    ).webapis?.network;
    const ip = network?.getIp?.();
    if (typeof ip === "string" && ipv4Parts(ip) && !seen.has(ip)) {
      seen.add(ip);
      ips.push(ip);
    }
  } catch {
    /* platform API unavailable */
  }

  return ips;
}
