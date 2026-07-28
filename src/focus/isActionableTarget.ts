/**
 * True when Enter/Space should activate the focused control instead of a
 * screen-level shortcut (e.g. player play/pause).
 *
 * Disconnected nodes (chrome unmounted mid-focus) must not count — otherwise
 * OK is swallowed and neither the dead button nor the player shortcut runs.
 */
export function isActionableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element) || !target.isConnected) return false;
  return Boolean(
    target.closest("button, [role='button'], a[href], input, select, textarea, summary"),
  );
}
