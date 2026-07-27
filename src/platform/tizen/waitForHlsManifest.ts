/**
 * Poll until an HLS master/media playlist contains #EXTM3U.
 * AVPlay open on a not-yet-written remux/transcode manifest fails the whole
 * pipeline (brief error → dead player), so wait before open/prepare.
 *
 * Resolves true when ready, false on timeout (caller may still try open).
 */
export async function waitForHlsManifest(
  url: string,
  options: { intervalMs?: number; timeoutMs?: number; fetchImpl?: typeof fetch } = {},
): Promise<boolean> {
  const intervalMs = options.intervalMs ?? 500;
  const timeoutMs = options.timeoutMs ?? 15_000;
  const fetchImpl = options.fetchImpl ?? fetch;
  const deadline = Date.now() + timeoutMs;

  const fetchText = async (): Promise<string> => {
    try {
      const controller = new AbortController();
      const timer = window.setTimeout(() => controller.abort(), 5_000);
      try {
        const res = await fetchImpl(url, {
          cache: "no-store",
          signal: controller.signal,
        });
        if (!res.ok) return "";
        return await res.text();
      } finally {
        window.clearTimeout(timer);
      }
    } catch {
      return "";
    }
  };

  while (Date.now() < deadline) {
    const body = await fetchText();
    if (body.includes("#EXTM3U")) return true;
    await new Promise((resolve) => window.setTimeout(resolve, intervalMs));
  }
  return false;
}

export function isHlsUrl(url: string): boolean {
  const path = url.split("?")[0]?.toLowerCase() ?? "";
  return path.endsWith(".m3u8") || path.includes("/hls") || path.includes("master.m3u8");
}
