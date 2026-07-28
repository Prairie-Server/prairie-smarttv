import type { PerformanceTier } from "../perf/performanceTier";

/**
 * Caps how many artwork images decode at once.
 *
 * Native `loading="lazy"` still starts every image within a generous distance of
 * the viewport — on a 1080p TV that is several rows' worth. Decoded surface is
 * what costs memory (a 300x450 poster is ~540 KB regardless of file size), so a
 * burst of them triggers garbage collection pauses that read as input lag.
 *
 * Eager images still go through the queue (so they cannot stampede the main
 * thread) but jump ahead of lazy work via a priority lane.
 */

/**
 * How many artwork loads may be in flight at once, by device tier.
 *
 * Keep this conservative: a flat 2 was what stopped multi-minute D-pad lock-ups
 * on mid-range Tizen after decode went async. Higher tiers may admit one extra
 * in-flight image; raising further needs on-device confirmation.
 */
const MAX_CONCURRENT_BY_TIER: Record<PerformanceTier, number> = {
  high: 3,
  balanced: 2,
  low: 2,
};

/**
 * How long a single load may hold its slot before we assume it stalled.
 *
 * The queue only advances when slots are released on load/error/unmount. A
 * stalled TCP connection on flaky TV Wi-Fi fires neither event, so its slot is
 * held indefinitely; with only 2-3 slots, a couple of stuck loads starve every
 * other poster/backdrop app-wide (including on screens navigated to later). The
 * watchdog frees the slot so queued work proceeds — the `<img>` keeps loading in
 * the background and still resolves if the socket recovers. Generous enough that
 * a legitimately slow load is not cut short.
 */
const SLOT_TIMEOUT_MS = 8000;

/** Default until `refreshImageLoadConcurrency` runs from boot / settings. */
let maxConcurrentLoads = MAX_CONCURRENT_BY_TIER.low;

/** Re-read the tier (called when the performance mode setting changes). */
export function refreshImageLoadConcurrency(tier: PerformanceTier): number {
  maxConcurrentLoads = MAX_CONCURRENT_BY_TIER[tier];
  pump();
  return maxConcurrentLoads;
}

let active = 0;
const priorityWaiting: Array<() => void> = [];
const waiting: Array<() => void> = [];

function pump(): void {
  while (active < maxConcurrentLoads && (priorityWaiting.length > 0 || waiting.length > 0)) {
    const next = priorityWaiting.shift() ?? waiting.shift();
    if (!next) return;
    active += 1;
    next();
  }
}

export type AcquireImageSlotOptions = {
  /** Jump ahead of lazy loads. Still respects the current concurrency cap. */
  priority?: boolean;
};

/**
 * Runs `start` once a slot is free. The returned function releases the slot and
 * must be called on load, error, or unmount; releasing twice is a no-op.
 */
export function acquireImageSlot(
  start: () => void,
  options: AcquireImageSlotOptions = {},
): () => void {
  let released = false;
  let started = false;
  let watchdog: number | null = null;
  const lane = options.priority ? priorityWaiting : waiting;

  const begin = () => {
    started = true;
    if (typeof window !== "undefined") {
      // Free the slot if this load never reports back (stalled socket), so it
      // cannot wedge the shared queue. release() is a no-op when the real
      // load/error fires afterward.
      watchdog = window.setTimeout(release, SLOT_TIMEOUT_MS);
    }
    start();
  };

  const release = () => {
    if (released) return;
    released = true;
    if (watchdog != null) {
      window.clearTimeout(watchdog);
      watchdog = null;
    }
    if (started) {
      active = Math.max(0, active - 1);
      pump();
      return;
    }
    const index = lane.indexOf(begin);
    if (index >= 0) lane.splice(index, 1);
  };

  lane.push(begin);
  pump();
  return release;
}

/** @internal Test helper. */
export function resetImageLoadQueueForTests(tier: PerformanceTier = "low"): void {
  active = 0;
  priorityWaiting.length = 0;
  waiting.length = 0;
  maxConcurrentLoads = MAX_CONCURRENT_BY_TIER[tier];
}

/** @internal Test helper. */
export function imageLoadQueueDepth(): {
  active: number;
  waiting: number;
  priorityWaiting: number;
} {
  return {
    active,
    waiting: waiting.length,
    priorityWaiting: priorityWaiting.length,
  };
}
