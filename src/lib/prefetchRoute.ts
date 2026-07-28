/**
 * Warm a code-split screen's chunk before the viewer asks for it.
 *
 * Screens are lazily imported so launch only parses what the first paint needs,
 * which is the right trade on a TV — but it puts chunk fetch, parse and compile
 * directly in the critical path of the *next* navigation. Pressing OK on a
 * poster showed a blank `aria-busy` shell while the detail chunk loaded, before
 * its first request had even been issued.
 *
 * Navigation on a TV is highly predictable: from any browse screen the next
 * screen is nearly always the detail page, and from the detail page it is the
 * player. Loading those chunks while the device is idle moves that cost off the
 * critical path entirely, and the module registry means the subsequent `lazy()`
 * import resolves from memory.
 *
 * Each key is attempted once per app lifetime. A failed prefetch is ignored: the
 * real navigation will import again and surface any error through Suspense.
 */

/** Keys already scheduled, so repeated renders cannot queue duplicate work. */
const started = new Set<string>();

type IdleWindow = Window & {
  requestIdleCallback?: (callback: () => void, options?: { timeout: number }) => number;
};

/**
 * Run `task` when the main thread is next idle.
 *
 * `requestIdleCallback` is absent on several TV WebViews (and in the test DOM),
 * so fall back to a timeout long enough to sit behind the current screen's own
 * first paint and requests rather than competing with them.
 */
function whenIdle(task: () => void, timeoutMs: number): () => void {
  if (typeof window === "undefined") return () => undefined;
  const idleWindow = window as IdleWindow;
  if (typeof idleWindow.requestIdleCallback === "function") {
    idleWindow.requestIdleCallback(task, { timeout: timeoutMs });
    // Idle callbacks cannot be cancelled portably here; the guard below makes a
    // late run harmless.
    return () => undefined;
  }
  const handle = window.setTimeout(task, timeoutMs);
  return () => window.clearTimeout(handle);
}

/**
 * Schedule a one-shot chunk prefetch for `key`.
 *
 * Returns a cleanup that cancels the pending schedule, so an unmount before the
 * idle slot arrives does not start work for a screen the viewer left.
 */
export function prefetchRoute(
  key: string,
  load: () => Promise<unknown>,
  timeoutMs = 1500,
): () => void {
  if (started.has(key)) return () => undefined;
  let cancelled = false;
  const cancelIdle = whenIdle(() => {
    if (cancelled || started.has(key)) return;
    started.add(key);
    void load().catch(() => {
      // Navigation will import again and report the failure properly.
      started.delete(key);
    });
  }, timeoutMs);
  return () => {
    cancelled = true;
    cancelIdle();
  };
}

/** @internal Test helper. */
export function resetPrefetchedRoutesForTests(): void {
  started.clear();
}
