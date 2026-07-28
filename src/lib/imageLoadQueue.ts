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

const MAX_CONCURRENT_LOADS = 4;

let active = 0;
const priorityWaiting: Array<() => void> = [];
const waiting: Array<() => void> = [];

function pump(): void {
  while (active < MAX_CONCURRENT_LOADS && (priorityWaiting.length > 0 || waiting.length > 0)) {
    const next = priorityWaiting.shift() ?? waiting.shift();
    if (!next) return;
    active += 1;
    next();
  }
}

export type AcquireImageSlotOptions = {
  /** Jump ahead of lazy loads. Still respects MAX_CONCURRENT_LOADS. */
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
  const lane = options.priority ? priorityWaiting : waiting;

  const begin = () => {
    started = true;
    start();
  };

  const release = () => {
    if (released) return;
    released = true;
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
export function resetImageLoadQueueForTests(): void {
  active = 0;
  priorityWaiting.length = 0;
  waiting.length = 0;
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
