import type { ArrowKey } from "./spatialFocusKeys";

export type { ArrowKey } from "./spatialFocusKeys";
export {
  isArrowKey,
  isBackKey,
  isEditableTarget,
  shouldDeferToEditableCaret,
} from "./spatialFocusKeys";

import {
  isArrowKey,
  isEditableTarget,
  shouldDeferToEditableCaret,
} from "./spatialFocusKeys";

/** Sync reveal when virtualized containers need to mount an off-window index. */
export type FocusRevealHandler = (index: number) => HTMLElement | null;

const revealHandlers = new WeakMap<HTMLElement, FocusRevealHandler>();
const lastIndexByContainer = new WeakMap<HTMLElement, number>();

export function registerFocusReveal(container: HTMLElement, handler: FocusRevealHandler): () => void {
  revealHandlers.set(container, handler);
  return () => {
    revealHandlers.delete(container);
  };
}

function isRoughlyOnScreen(el: HTMLElement): boolean {
  const rect = el.getBoundingClientRect();
  if (rect.width <= 0 && rect.height <= 0) return false;
  const marginX = Math.max(window.innerWidth, 800);
  const marginY = Math.max(window.innerHeight * 0.75, 320);
  return (
    rect.bottom > -marginY &&
    rect.top < window.innerHeight + marginY &&
    rect.right > -marginX &&
    rect.left < window.innerWidth + marginX
  );
}

function isFocusableCandidate(el: HTMLElement): boolean {
  if (el.closest("[data-focus-trap='off']")) return false;
  if (el.getAttribute("aria-hidden") === "true") return false;
  if (
    el instanceof HTMLInputElement &&
    (el.type === "checkbox" || el.type === "radio") &&
    el.closest("button, [role='button'], .settings-row, .toggle-row")
  ) {
    return false;
  }
  const visible = el.offsetParent !== null || el === document.activeElement;
  return visible;
}

export function listFocusables(root: ParentNode = document): HTMLElement[] {
  return Array.from(
    root.querySelectorAll<HTMLElement>(
      'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
    ),
  ).filter((el) => {
    if (!isFocusableCandidate(el)) return false;
    if (el === document.activeElement) return true;
    if (root !== document && root !== document.body) return true;
    return isRoughlyOnScreen(el);
  });
}

function closestFocusContainer(el: HTMLElement | null): HTMLElement | null {
  return el?.closest<HTMLElement>("[data-focus-container]") ?? null;
}

/** Focusables that belong to this container (not a nested container). */
export function listContainerFocusables(container: HTMLElement): HTMLElement[] {
  return listFocusables(container).filter((el) => closestFocusContainer(el) === container);
}

function parseAbsoluteIndex(el: HTMLElement, fallback: number): number {
  const raw = el.dataset.focusIndex;
  if (raw == null || raw === "") return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function containerTotal(container: HTMLElement, renderedCount: number): number {
  const parsed = Number(container.dataset.focusCount);
  if (Number.isFinite(parsed) && parsed >= renderedCount) return parsed;
  return renderedCount;
}

function revealIndex(container: HTMLElement, index: number): HTMLElement | null {
  const handler = revealHandlers.get(container);
  if (handler) {
    const revealed = handler(index);
    if (revealed) return revealed;
  }
  return (
    container.querySelector<HTMLElement>(`[data-focus-index="${index}"]`) ??
    listContainerFocusables(container).find((el, i) => parseAbsoluteIndex(el, i) === index) ??
    null
  );
}

function focusAtContainerIndex(container: HTMLElement, index: number): HTMLElement | null {
  const items = listContainerFocusables(container);
  const total = containerTotal(container, items.length);
  if (total <= 0) return null;
  const clamped = Math.max(0, Math.min(index, total - 1));
  const existing = items.find((el, i) => parseAbsoluteIndex(el, i) === clamped);
  if (existing) {
    lastIndexByContainer.set(container, clamped);
    return existing;
  }
  const revealed = revealIndex(container, clamped);
  if (revealed) lastIndexByContainer.set(container, clamped);
  return revealed;
}

function estimateGridColumns(container: HTMLElement, items: HTMLElement[]): number {
  const parsed = Number(container.dataset.focusColumns);
  if (Number.isFinite(parsed) && parsed > 0) return Math.floor(parsed);
  if (items.length <= 1) return 1;
  const firstTop = items[0]!.getBoundingClientRect().top;
  let cols = 1;
  for (let i = 1; i < items.length; i++) {
    if (Math.abs(items[i]!.getBoundingClientRect().top - firstTop) > 8) break;
    cols += 1;
  }
  return cols;
}

function listFocusContainers(root: ParentNode = document): HTMLElement[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-focus-container]")).filter((el) => {
    if (el.closest("[data-focus-trap='off']")) return false;
    return el.offsetParent !== null || el.contains(document.activeElement);
  });
}

function findAcrossContainers(
  fromContainer: HTMLElement,
  key: "ArrowUp" | "ArrowDown",
  preferredIndex: number,
): HTMLElement | null {
  const containers = listFocusContainers();
  const fromIndex = containers.indexOf(fromContainer);
  if (fromIndex < 0) return null;
  const step = key === "ArrowDown" ? 1 : -1;
  for (let i = fromIndex + step; i >= 0 && i < containers.length; i += step) {
    const target = containers[i]!;
    const remembered = lastIndexByContainer.get(target);
    const next = focusAtContainerIndex(target, remembered ?? preferredIndex);
    if (next) return next;
  }
  return null;
}

function navigateContainer(
  active: HTMLElement,
  key: ArrowKey,
  container: HTMLElement,
): HTMLElement | null {
  const orientation = (container.dataset.focusContainer || "horizontal").toLowerCase();
  const items = listContainerFocusables(container);
  if (!items.length) return null;

  const localIndex = items.indexOf(active);
  const absoluteIndex = parseAbsoluteIndex(active, localIndex >= 0 ? localIndex : 0);
  const total = containerTotal(container, items.length);
  lastIndexByContainer.set(container, absoluteIndex);

  if (orientation === "grid") {
    const cols = estimateGridColumns(container, items);
    if (key === "ArrowLeft") {
      return absoluteIndex > 0 ? focusAtContainerIndex(container, absoluteIndex - 1) : active;
    }
    if (key === "ArrowRight") {
      return absoluteIndex < total - 1
        ? focusAtContainerIndex(container, absoluteIndex + 1)
        : active;
    }
    if (key === "ArrowUp") {
      if (absoluteIndex >= cols) {
        return focusAtContainerIndex(container, absoluteIndex - cols);
      }
      return findAcrossContainers(container, "ArrowUp", absoluteIndex % cols);
    }
    if (key === "ArrowDown") {
      if (absoluteIndex + cols < total) {
        return focusAtContainerIndex(container, absoluteIndex + cols);
      }
      return findAcrossContainers(container, "ArrowDown", absoluteIndex % cols);
    }
    /* v8 ignore next -- ArrowKey union is exhaustive above */
    return null;
  }

  // horizontal (default for rails) or vertical
  const forward = orientation === "vertical" ? "ArrowDown" : "ArrowRight";
  const backward = orientation === "vertical" ? "ArrowUp" : "ArrowLeft";
  const exitForward = orientation === "vertical" ? "ArrowRight" : "ArrowDown";
  const exitBackward = orientation === "vertical" ? "ArrowLeft" : "ArrowUp";

  if (key === forward && absoluteIndex < total - 1) {
    return focusAtContainerIndex(container, absoluteIndex + 1);
  }
  if (key === backward && absoluteIndex > 0) {
    return focusAtContainerIndex(container, absoluteIndex - 1);
  }
  if (key === exitForward) {
    return findAcrossContainers(container, "ArrowDown", absoluteIndex);
  }
  if (key === exitBackward) {
    return findAcrossContainers(container, "ArrowUp", absoluteIndex);
  }
  // Stay put at horizontal/vertical edges instead of geometry-jumping into another row mid-rail.
  if (key === forward || key === backward) return active;
  /* v8 ignore next -- exit keys already returned above */
  return null;
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
  options?: { looseHorizontal?: boolean },
): boolean {
  const dx = to.x - from.x;
  const dy = to.y - from.y;
  switch (key) {
    case "ArrowLeft":
    case "ArrowRight": {
      const rowSlop = options?.looseHorizontal
        ? Math.max(fromRect.height, toRect.height, 40) * 4.5
        : Math.max(fromRect.height, toRect.height, 40) * 0.75;
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

function pickNeighbor(
  active: HTMLElement,
  key: ArrowKey,
  candidates: HTMLElement[],
  looseHorizontal: boolean,
): HTMLElement | null {
  const fromRect = active.getBoundingClientRect();
  const from = center(fromRect);
  let best: HTMLElement | null = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (const candidate of candidates) {
    if (candidate === active) continue;
    const toRect = candidate.getBoundingClientRect();
    const to = center(toRect);
    if (!isInDirection(from, to, key, fromRect, toRect, { looseHorizontal })) continue;
    const score = scoreCandidate(from, to, key);
    if (score < bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return best;
}

/**
 * Prefer index navigation inside focus containers; fall back to geometry.
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

  const container = closestFocusContainer(active);
  if (container) {
    const indexed = navigateContainer(active, key, container);
    if (indexed) {
      // "Stay put" sentinel when already at an edge.
      if (indexed === active) return null;
      return indexed;
    }
  }

  const strict = pickNeighbor(active, key, candidates, false);
  if (strict) return strict;
  if (key === "ArrowLeft" || key === "ArrowRight") {
    return pickNeighbor(active, key, candidates, true);
  }
  return null;
}

function focusWithoutPageJump(el: HTMLElement): void {
  el.focus({ preventScroll: true });
  const rect = el.getBoundingClientRect();
  const fullyVisible =
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <= window.innerHeight &&
    rect.right <= window.innerWidth;
  if (!fullyVisible) {
    el.scrollIntoView({ block: "nearest", inline: "nearest" });
  }
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
