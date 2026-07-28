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
 * Repaint after the current commit has painted, then once more a beat later —
 * the hole is sometimes still torn down when the first frame runs.
 */
export function scheduleCompositorRepaint(): void {
  if (typeof window === "undefined") return;
  const run = () => forceCompositorRepaint();
  if (typeof window.requestAnimationFrame === "function") {
    window.requestAnimationFrame(run);
  } else {
    window.setTimeout(run, 0);
  }
  window.setTimeout(run, 250);
}
