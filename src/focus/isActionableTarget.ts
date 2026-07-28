/**
 * True when Enter/Space should activate the focused control instead of a
 * screen-level shortcut (e.g. player play/pause).
 */
export function isActionableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof Element)) return false;
  return Boolean(
    target.closest("button, [role='button'], a[href], input, select, textarea, summary"),
  );
}
