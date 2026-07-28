/**
 * Force the TV WebView to recomposite the whole page.
 *
 * Tizen composites AVPlay onto a hardware plane punched through the WebView.
 * After `avplay.close()` some firmwares never invalidate the layers that were
 * behind that hole, so the next screen paints its body background but none of
 * its content — the app looks empty until something else forces a repaint.
 *
 * Toggling `display` on the React root invalidates the layer tree; the forced
 * reflow between the two writes is what makes the browser honour both.
 */
export function forceCompositorRepaint(): void {
  if (typeof document === "undefined") return;
  const root = document.getElementById("root") ?? document.body;
  if (!root) return;
  const previous = root.style.display;
  root.style.display = "none";
  // Read a layout property so the "none" is not coalesced away with the restore.
  void root.offsetHeight;
  root.style.display = previous;
}

/**
 * Delays (ms) at which we re-invalidate the compositor after a player teardown.
 *
 * The screen we return to is lazy-loaded and fetches its data asynchronously, so
 * on a slow TV it often does not paint its real content until well after the
 * player unmounts. A single early repaint invalidates the hole while the
 * destination is still blank and then never fires again once the content lands —
 * leaving the wallpaper-only "dead" shell. Retrying on a decaying schedule that
 * spans a realistic content-load window covers the late paint. Each pass is a
 * one-frame invisible display toggle, so extra passes are cheap and unseen.
 */
const REPAINT_SCHEDULE_MS = [150, 400, 800, 1500] as const;

let pendingRepaintTimers: number[] = [];
let pendingRepaintFrame: number | null = null;
/**
 * Bumped on every cancel/schedule so a frame callback that is already queued
 * cannot repaint for a schedule we abandoned. `cancelAnimationFrame` is not
 * enough on its own — the rAF may be mid-flight, and a stale pass toggling
 * `display` on the *next* screen is exactly the flicker we are avoiding.
 */
let repaintGeneration = 0;

/** Cancel any repaint passes still queued from a previous schedule. */
export function cancelScheduledCompositorRepaint(): void {
  repaintGeneration += 1;
  if (typeof window === "undefined") return;
  for (const id of pendingRepaintTimers) window.clearTimeout(id);
  pendingRepaintTimers = [];
  if (pendingRepaintFrame != null && typeof window.cancelAnimationFrame === "function") {
    window.cancelAnimationFrame(pendingRepaintFrame);
  }
  pendingRepaintFrame = null;
}

/**
 * Repaint after the current commit has painted, then again across a decaying
 * window so a slow destination screen that paints late is still un-holed.
 * Cancels any schedule already in flight so repeated calls do not stack.
 */
export function scheduleCompositorRepaint(): void {
  if (typeof window === "undefined") return;
  cancelScheduledCompositorRepaint();
  const generation = repaintGeneration;
  const run = () => {
    // A cancel (or a newer schedule) between queueing and firing invalidates us.
    if (generation !== repaintGeneration) return;
    forceCompositorRepaint();
  };
  if (typeof window.requestAnimationFrame === "function") {
    pendingRepaintFrame = window.requestAnimationFrame(() => {
      pendingRepaintFrame = null;
      run();
    });
  } else {
    pendingRepaintTimers.push(window.setTimeout(run, 0));
  }
  for (const delay of REPAINT_SCHEDULE_MS) {
    pendingRepaintTimers.push(window.setTimeout(run, delay));
  }
}
