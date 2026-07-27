import {
  HEALTH_PATH,
  buildCandidates,
  localIpv4Addresses,
  mergeHits,
  parseHealth,
  type DiscoveryHit,
} from "./discover";
import { normalizeServerUrl } from "../storage/persist";

export interface ScanOptions {
  extraCidrs?: string[];
  /** When true, sweep full /24 ranges on :8080. Default false (priority hosts). */
  deepScan?: boolean;
  maxHostsPerCidr?: number;
  concurrency?: number;
  timeoutMs?: number;
  signal?: AbortSignal;
  localIps?: string[];
  /** Hostnames to probe for cross-subnet discovery (resolved via unicast DNS). */
  baseHosts?: string[];
  fetchImpl?: typeof fetch;
  onHit?: (hits: DiscoveryHit[]) => void;
  onProgress?: (done: number, total: number) => void;
}

async function probeHealth(
  baseUrl: string,
  timeoutMs: number,
  fetchImpl: typeof fetch,
  signal?: AbortSignal,
): Promise<DiscoveryHit | null> {
  const serverUrl = normalizeServerUrl(baseUrl);
  const controller = new AbortController();
  const onAbort = () => controller.abort();
  if (signal) {
    if (signal.aborted) return null;
    signal.addEventListener("abort", onAbort, { once: true });
  }
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(`${serverUrl}${HEALTH_PATH}`, {
      method: "GET",
      signal: controller.signal,
      headers: {
        Accept: "application/json",
        "X-Prairie-Device-Platform": "smarttv",
        "X-Prairie-Device-Name": "Prairie Smart TV",
      },
    });
    if (!response.ok) return null;
    const data: unknown = await response.json();
    const health = parseHealth(data);
    if (!health) return null;
    return {
      url: serverUrl,
      serverName: health.serverName,
      serverId: health.serverId,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }
}

/**
 * Probe Prairie health across LAN candidates. SmartTV can run many fetches in
 * parallel (unlike Roku's serial HttpTask). Prefer a priority pass first, then
 * an optional deep pass from the UI.
 */
export async function runLanDiscovery(options: ScanOptions = {}): Promise<DiscoveryHit[]> {
  const {
    extraCidrs = [],
    deepScan = false,
    maxHostsPerCidr = 254,
    concurrency = 24,
    timeoutMs = 400,
    signal,
    fetchImpl = fetch,
    baseHosts,
    onHit,
    onProgress,
  } = options;
  const localIps = options.localIps ?? localIpv4Addresses();
  const candidates = buildCandidates({
    extraCidrs,
    deepScan,
    maxHostsPerCidr,
    localIps,
    baseHosts,
  });

  const hits: DiscoveryHit[] = [];
  let done = 0;
  let next = 0;

  async function worker(): Promise<void> {
    while (next < candidates.length) {
      if (signal?.aborted) return;
      const index = next;
      next += 1;
      const url = candidates[index]!;
      const hit = await probeHealth(url, timeoutMs, fetchImpl, signal);
      done += 1;
      onProgress?.(done, candidates.length);
      if (hit) {
        mergeHits(hits, hit.url, hit);
        onHit?.([...hits]);
      }
    }
  }

  const workers = Array.from({ length: Math.min(concurrency, candidates.length) }, () => worker());
  await Promise.all(workers);
  return hits;
}
