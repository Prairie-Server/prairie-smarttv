export type ArrowKey = "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight";

export function isArrowKey(key: string): key is ArrowKey {
  return key === "ArrowUp" || key === "ArrowDown" || key === "ArrowLeft" || key === "ArrowRight";
}

/** Text-entry fields where arrows should move the caret, not spatial focus. */
export function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target instanceof HTMLTextAreaElement) return true;
  if (target instanceof HTMLSelectElement) return true;
  if (target.isContentEditable) return true;
  if (!(target instanceof HTMLInputElement)) return false;
  const type = (target.type || "text").toLowerCase();
  // Checkboxes/radios/buttons must stay in spatial nav (TV remote).
  return (
    type === "text" ||
    type === "password" ||
    type === "search" ||
    type === "email" ||
    type === "url" ||
    type === "tel" ||
    type === "number" ||
    type === ""
  );
}

/**
 * Whether an arrow key should stay on the caret inside an editable field.
 * Up/Down always leave the field on TV remotes so users can reach Back / QR.
 * Left/Right keep caret motion until the selection is at the field edge.
 */
export function shouldDeferToEditableCaret(target: EventTarget | null, key: ArrowKey): boolean {
  if (!isEditableTarget(target)) return false;
  if (key === "ArrowUp" || key === "ArrowDown") return false;
  if (!(target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) {
    return true;
  }
  const start = target.selectionStart;
  const end = target.selectionEnd;
  if (start == null || end == null) return true;
  if (start !== end) return true;
  if (key === "ArrowLeft") return start > 0;
  if (key === "ArrowRight") return start < target.value.length;
  return true;
}

function isRoughlyOnScreen(el: HTMLElement): boolean {
  const rect = el.getBoundingClientRect();
  if (rect.width <= 0 && rect.height <= 0) return false;
  // Keep wide horizontal margins so in-row posters stay candidates.
  const marginX = Math.max(window.innerWidth, 800);
  const marginY = Math.max(window.innerHeight * 0.75, 320);
  return (
    rect.bottom > -marginY &&
    rect.top < window.innerHeight + marginY &&
    rect.right > -marginX &&
    rect.left < window.innerWidth + marginX
  );
}

export function listFocusables(root: ParentNode = document): HTMLElement[] {
  return Array.from(
    root.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ),
  ).filter((el) => {
    if (el.closest("[data-focus-trap='off']")) return false;
    if (el.getAttribute("aria-hidden") === "true") return false;
    // Native checkboxes/radios inside a focusable row should not be separate targets.
    if (
      el instanceof HTMLInputElement &&
      (el.type === "checkbox" || el.type === "radio") &&
      el.closest("button, [role='button'], .settings-row, .toggle-row")
    ) {
      return false;
    }
    const visible = el.offsetParent !== null || el === document.activeElement;
    if (!visible) return false;
    if (el === document.activeElement) return true;
    return isRoughlyOnScreen(el);
  });
}

interface Point {
  x: number;
  y: number;
}

function center(rect: DOMRect): Point {
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
}

function isInDirection(
  from: Point,
  to: Point,
  key: ArrowKey,
  fromRect: DOMRect,
  toRect: DOMRect,
): boolean {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  switch (key) {
    case "ArrowLeft":
    case "ArrowRight": {
      // Keep left/right on the same row so full-width inputs above a button row
      // (e.g. password) don't steal focus when moving between action buttons.
      const rowSlop = Math.max(fromRect.height, toRect.height, 40) * 0.75;
      if (Math.abs(dy) > rowSlop) return false;
      return key === "ArrowLeft" ? dx < -2 : dx > 2;
    }
    case "ArrowUp":
      return dy < -2 && Math.abs(dy) >= Math.abs(dx) * 0.35;
    case "ArrowDown":
      return dy > 2 && Math.abs(dy) >= Math.abs(dx) * 0.35;
  }
}

function scoreCandidate(from: Point, to: Point, key: ArrowKey): number {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const primary = key === "ArrowLeft" || key === "ArrowRight" ? Math.abs(dx) : Math.abs(dy);
  const secondary = key === "ArrowLeft" || key === "ArrowRight" ? Math.abs(dy) : Math.abs(dx);
  return primary * 1000 + secondary;
}

/**
 * Pick the nearest focusable in the arrow direction using geometry, not DOM order.
 * Falls back to null when nothing lies in that direction.
 */
export function findSpatialNeighbor(
  active: HTMLElement | null,
  key: ArrowKey,
  candidates: HTMLElement[] = listFocusables(),
): HTMLElement | null {
  if (!candidates.length) return null;
  if (!active || !candidates.includes(active)) {
    return candidates[0] ?? null;
  }

  const fromRect = active.getBoundingClientRect();
  const from = center(fromRect);
  let best: HTMLElement | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (const candidate of candidates) {
    if (candidate === active) continue;
    const toRect = candidate.getBoundingClientRect();
    const to = center(toRect);
    if (!isInDirection(from, to, key, fromRect, toRect)) continue;
    const score = scoreCandidate(from, to, key);
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return best;
}

function focusWithoutPageJump(el: HTMLElement): void {
  el.focus({ preventScroll: true });
  el.scrollIntoView({ block: "nearest", inline: "nearest" });
}

/** Handle an arrow keydown with spatial focus. Returns true when focus moved. */
export function handleSpatialArrowKey(event: KeyboardEvent): boolean {
  if (!isArrowKey(event.key)) return false;
  if (event.defaultPrevented) return false;
  if (event.altKey || event.ctrlKey || event.metaKey) return false;
  if (shouldDeferToEditableCaret(event.target, event.key)) return false;
  const focusables = listFocusables();
  if (focusables.length < 2) return false;
  const active =
    (isEditableTarget(event.target) ? (event.target as HTMLElement) : null) ??
    (document.activeElement as HTMLElement | null);
  const next = findSpatialNeighbor(active, event.key, focusables);
  if (!next) return false;
  if (isEditableTarget(event.target) && event.target instanceof HTMLElement) {
    event.target.blur();
  }
  focusWithoutPageJump(next);
  event.preventDefault();
  return true;
}

/** TV remote Back / Escape helpers. */
export function isBackKey(key: string): boolean {
  return key === "Escape" || key === "Backspace" || key === "XF86Back" || key === "GoBack";
}
