export type ArrowKey = "ArrowUp" | "ArrowDown" | "ArrowLeft" | "ArrowRight";

export function isArrowKey(key: string): key is ArrowKey {
  return key === "ArrowUp" || key === "ArrowDown" || key === "ArrowLeft" || key === "ArrowRight";
}

export function listFocusables(root: ParentNode = document): HTMLElement[] {
  return Array.from(
    root.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ),
  ).filter((el) => {
    if (el.closest("[data-focus-trap='off']")) return false;
    return el.offsetParent !== null || el === document.activeElement;
  });
}

interface Point {
  x: number;
  y: number;
}

function center(rect: DOMRect): Point {
  return { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
}

function isInDirection(from: Point, to: Point, key: ArrowKey): boolean {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  switch (key) {
    case "ArrowLeft":
      return dx < -2 && Math.abs(dx) >= Math.abs(dy) * 0.35;
    case "ArrowRight":
      return dx > 2 && Math.abs(dx) >= Math.abs(dy) * 0.35;
    case "ArrowUp":
      return dy < -2 && Math.abs(dy) >= Math.abs(dx) * 0.35;
    case "ArrowDown":
      return dy > 2 && Math.abs(dy) >= Math.abs(dx) * 0.35;
  }
}

function scoreCandidate(from: Point, to: Point, key: ArrowKey): number {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  const primary =
    key === "ArrowLeft" || key === "ArrowRight" ? Math.abs(dx) : Math.abs(dy);
  const secondary =
    key === "ArrowLeft" || key === "ArrowRight" ? Math.abs(dy) : Math.abs(dx);
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

  const from = center(active.getBoundingClientRect());
  let best: HTMLElement | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (const candidate of candidates) {
    if (candidate === active) continue;
    const to = center(candidate.getBoundingClientRect());
    if (!isInDirection(from, to, key)) continue;
    const score = scoreCandidate(from, to, key);
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return best;
}

/** Handle an arrow keydown with spatial focus. Returns true when focus moved. */
export function handleSpatialArrowKey(event: KeyboardEvent): boolean {
  if (!isArrowKey(event.key)) return false;
  const focusables = listFocusables();
  if (focusables.length < 2) return false;
  const active = document.activeElement as HTMLElement | null;
  const next = findSpatialNeighbor(active, event.key, focusables);
  if (!next) return false;
  next.focus();
  event.preventDefault();
  return true;
}
