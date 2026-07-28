/**
 * Poll until an HLS playlist is playable: #EXTM3U present and (optionally)
 * the first media segment is fetchable. AVPlay open on a not-yet-written
 * remux/transcode pipeline fails the whole player; encoded sessions also
 * expose a synthetic VOD playlist before the window-head segment exists, so
 * checking only #EXTM3U is not enough.
 *
 * Throws TranscodeStartupTimeoutError when the deadline elapses without a
 * ready segment so callers can show "Transcode timed out" instead of hanging.
 */

export class TranscodeStartupTimeoutError extends Error {
  constructor(message = "Transcode timed out") {
    super(message);
    this.name = "TranscodeStartupTimeoutError";
  }
}

export interface WaitForHlsManifestOptions {
  intervalMs?: number;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
  /** When true (default), require the first media segment to return HTTP 200. */
  requireSegment?: boolean;
  /** Fired periodically during the wait (e.g. POST /playback/.../progress). */
  onKeepAlive?: () => void | Promise<void>;
  keepAliveEveryMs?: number;
  /**
   * Stops polling (and its keepalives) when aborted. Without it, navigating away
   * from a slow-starting transcode leaves this loop running and posting progress
   * keepalives that actively hold the server session alive until it times out.
   */
  signal?: AbortSignal;
}

/**
 * Per-request controller that also aborts when the caller's signal does.
 *
 * `AbortSignal.any` is not available on the Tizen WebViews we target, so chain
 * the parent by hand. Without this the caller's abort only takes effect between
 * poll iterations — a navigate-away during a 12s segment probe keeps the loop
 * (and its session-holding keepalives) running until that fetch settles.
 */
function linkedController(
  parent: AbortSignal | undefined,
  abortMs: number,
): { controller: AbortController; dispose: () => void } {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), abortMs);
  const onParentAbort = () => controller.abort();
  // The poll loop re-checks `aborted` before every call, so an already-aborted
  // parent never reaches here — listening is enough.
  parent?.addEventListener("abort", onParentAbort);
  return {
    controller,
    dispose: () => {
      window.clearTimeout(timer);
      parent?.removeEventListener("abort", onParentAbort);
    },
  };
}

async function fetchText(
  url: string,
  fetchImpl: typeof fetch,
  abortMs: number,
  signal?: AbortSignal,
): Promise<{ ok: boolean; status: number; body: string }> {
  try {
    const { controller, dispose } = linkedController(signal, abortMs);
    try {
      const res = await fetchImpl(url, {
        cache: "no-store",
        signal: controller.signal,
      });
      const body = res.ok ? await res.text() : "";
      return { ok: res.ok, status: res.status, body };
    } finally {
      dispose();
    }
  } catch {
    return { ok: false, status: 0, body: "" };
  }
}

async function segmentReady(
  url: string,
  fetchImpl: typeof fetch,
  signal?: AbortSignal,
): Promise<boolean> {
  try {
    const { controller, dispose } = linkedController(signal, 12_000);
    try {
      // Prefer a cheap probe; some stacks reject HEAD — fall back to GET.
      let res = await fetchImpl(url, {
        method: "HEAD",
        cache: "no-store",
        signal: controller.signal,
      });
      if (res.status === 405 || res.status === 501) {
        res = await fetchImpl(url, {
          method: "GET",
          cache: "no-store",
          signal: controller.signal,
          headers: { Range: "bytes=0-0" },
        });
      }
      return res.ok || res.status === 206;
    } finally {
      dispose();
    }
  } catch {
    return false;
  }
}

/** Resolve the first media segment URI from an m3u8 body relative to the playlist URL. */
export function firstMediaSegmentUrl(playlistUrl: string, body: string): string | null {
  for (const rawLine of body.split("\n")) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    try {
      const resolved = new URL(line, playlistUrl);
      // Relative segment lines omit the playlist query (auth token). Carry it
      // over so segment probes use the same credentials as the manifest.
      if (!resolved.search) {
        const base = new URL(playlistUrl);
        if (base.search) resolved.search = base.search;
      }
      return resolved.toString();
    } catch {
      return null;
    }
  }
  return null;
}

/** Sleep that wakes early when the caller aborts, so exit is not delayed a backoff. */
function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    const done = () => {
      window.clearTimeout(timer);
      signal?.removeEventListener("abort", done);
      resolve();
    };
    const timer = window.setTimeout(done, ms);
    signal?.addEventListener("abort", done, { once: true });
  });
}

/**
 * Wait until the HLS playlist (and optionally first segment) is ready.
 * Resolves true when ready; throws TranscodeStartupTimeoutError on timeout
 * when `throwOnTimeout` is true (default). When throwOnTimeout is false,
 * resolves false on timeout (legacy AVPlay soft-continue behavior).
 */
export async function waitForHlsManifest(
  url: string,
  options: WaitForHlsManifestOptions & { throwOnTimeout?: boolean } = {},
): Promise<boolean> {
  const intervalMs = options.intervalMs ?? 500;
  const timeoutMs = options.timeoutMs ?? 90_000;
  const fetchImpl = options.fetchImpl ?? fetch;
  const requireSegment = options.requireSegment ?? true;
  const keepAliveEveryMs = options.keepAliveEveryMs ?? 10_000;
  const throwOnTimeout = options.throwOnTimeout ?? false;
  const deadline = Date.now() + timeoutMs;
  let delay = intervalMs;
  let nextKeepAliveAt = Date.now();

  const signal = options.signal;

  while (Date.now() < deadline) {
    // Bail the moment the caller navigates away so we stop holding the session.
    // Re-checked after every await below: the fetches and the backoff sleep are
    // seconds long, and each one is time the server session stays pinned.
    if (signal?.aborted) return false;
    if (options.onKeepAlive && Date.now() >= nextKeepAliveAt) {
      try {
        await options.onKeepAlive();
      } catch {
        // Keepalive is best-effort — never abort readiness polling on it.
      }
      if (signal?.aborted) return false;
      nextKeepAliveAt = Date.now() + keepAliveEveryMs;
    }

    const { ok, body } = await fetchText(url, fetchImpl, 8_000, signal);
    if (signal?.aborted) return false;
    if (ok && body.includes("#EXTM3U")) {
      if (!requireSegment) return true;
      // Encoded sessions serve a synthetic VOD playlist immediately; wait until
      // the first listed segment exists so AVPlay does not hang on open.
      if (!body.includes("#EXTINF")) {
        // Empty / master-only playlist — keep polling.
      } else {
        const segmentUrl = firstMediaSegmentUrl(url, body);
        if (segmentUrl) {
          const ready = await segmentReady(segmentUrl, fetchImpl, signal);
          if (signal?.aborted) return false;
          if (ready) return true;
        }
      }
    }

    await sleep(delay, signal);
    if (signal?.aborted) return false;
    delay = Math.min(Math.round(delay * 1.5), 4_000);
  }

  if (throwOnTimeout) {
    throw new TranscodeStartupTimeoutError();
  }
  return false;
}

export function isHlsUrl(url: string): boolean {
  const path = url.split("?")[0]?.toLowerCase() ?? "";
  return path.endsWith(".m3u8") || path.includes("/hls") || path.includes("master.m3u8");
}
