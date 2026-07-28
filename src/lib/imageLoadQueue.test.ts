import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  acquireImageSlot,
  imageLoadQueueDepth,
  refreshImageLoadConcurrency,
  resetImageLoadQueueForTests,
} from "./imageLoadQueue";

beforeEach(() => {
  resetImageLoadQueueForTests();
});

describe("imageLoadQueue", () => {
  it("starts up to the tier cap and queues the rest", () => {
    resetImageLoadQueueForTests("low");
    const started = Array.from({ length: 4 }, () => vi.fn());
    const releases = started.map((start) => acquireImageSlot(start));

    expect(started.filter((s) => s.mock.calls.length > 0)).toHaveLength(2);
    expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 2, priorityWaiting: 0 });

    // Finishing one load admits the next.
    releases[0]?.();
    expect(started[2]).toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 1, priorityWaiting: 0 });

    releases[1]?.();
    expect(started[3]).toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 0, priorityWaiting: 0 });
  });

  it("raises the cap on the high tier", () => {
    resetImageLoadQueueForTests("high");
    const started = Array.from({ length: 4 }, () => vi.fn());
    started.map((start) => acquireImageSlot(start));
    expect(started.filter((s) => s.mock.calls.length > 0)).toHaveLength(3);
    expect(imageLoadQueueDepth().active).toBe(3);
  });

  it("refreshImageLoadConcurrency updates the live cap", () => {
    resetImageLoadQueueForTests("low");
    expect(refreshImageLoadConcurrency("high")).toBe(3);
    const started = Array.from({ length: 4 }, () => vi.fn());
    started.map((start) => acquireImageSlot(start));
    expect(imageLoadQueueDepth().active).toBe(3);
  });

  it("starts priority loads ahead of lazy ones when a slot frees", () => {
    const lazy = Array.from({ length: 2 }, () => vi.fn());
    const releases = lazy.map((start) => acquireImageSlot(start));
    const lateLazy = vi.fn();
    const priority = vi.fn();
    acquireImageSlot(lateLazy);
    acquireImageSlot(priority, { priority: true });

    expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 1, priorityWaiting: 1 });

    releases[0]?.();
    expect(priority).toHaveBeenCalled();
    expect(lateLazy).not.toHaveBeenCalled();
  });

  it("drops a queued load that is released before it starts", () => {
    const started = Array.from({ length: 3 }, () => vi.fn());
    const releases = started.map((start) => acquireImageSlot(start));

    // The third is still waiting; releasing it must not consume a slot later.
    releases[2]?.();
    expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 0, priorityWaiting: 0 });

    releases[0]?.();
    expect(started[2]).not.toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 1, waiting: 0, priorityWaiting: 0 });
  });

  it("ignores repeated releases", () => {
    const start = vi.fn();
    const release = acquireImageSlot(start);
    release();
    release();
    release();
    expect(imageLoadQueueDepth()).toEqual({ active: 0, waiting: 0, priorityWaiting: 0 });
  });

  it("auto-releases a stalled slot so a wedged load cannot starve the queue", () => {
    vi.useFakeTimers();
    try {
      resetImageLoadQueueForTests("low");
      const started = Array.from({ length: 3 }, () => vi.fn());
      acquireImageSlot(started[0]!); // starts, then stalls (never releases)
      acquireImageSlot(started[1]!); // starts, then stalls
      const late = acquireImageSlot(started[2]!); // queued behind the two stalled

      expect(imageLoadQueueDepth()).toEqual({ active: 2, waiting: 1, priorityWaiting: 0 });
      expect(started[2]).not.toHaveBeenCalled();

      // Both stalled slots time out and free, admitting the queued load.
      vi.advanceTimersByTime(8000);
      expect(started[2]).toHaveBeenCalled();

      // The real load reporting back later is a harmless no-op.
      late();
      expect(imageLoadQueueDepth().active).toBeLessThanOrEqual(1);
    } finally {
      vi.useRealTimers();
    }
  });
});
