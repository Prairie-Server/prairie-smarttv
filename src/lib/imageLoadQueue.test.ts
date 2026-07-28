import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  acquireImageSlot,
  imageLoadQueueDepth,
  resetImageLoadQueueForTests,
} from "./imageLoadQueue";

beforeEach(() => {
  resetImageLoadQueueForTests();
});

describe("imageLoadQueue", () => {
  it("starts up to four loads and queues the rest", () => {
    const started = Array.from({ length: 6 }, () => vi.fn());
    const releases = started.map((start) => acquireImageSlot(start));

    expect(started.filter((s) => s.mock.calls.length > 0)).toHaveLength(4);
    expect(imageLoadQueueDepth()).toEqual({ active: 4, waiting: 2, priorityWaiting: 0 });

    // Finishing one load admits the next.
    releases[0]?.();
    expect(started[4]).toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 4, waiting: 1, priorityWaiting: 0 });

    releases[1]?.();
    expect(started[5]).toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 4, waiting: 0, priorityWaiting: 0 });
  });

  it("starts priority loads ahead of lazy ones when a slot frees", () => {
    const lazy = Array.from({ length: 4 }, () => vi.fn());
    const releases = lazy.map((start) => acquireImageSlot(start));
    const lateLazy = vi.fn();
    const priority = vi.fn();
    acquireImageSlot(lateLazy);
    acquireImageSlot(priority, { priority: true });

    expect(imageLoadQueueDepth()).toEqual({ active: 4, waiting: 1, priorityWaiting: 1 });

    releases[0]?.();
    expect(priority).toHaveBeenCalled();
    expect(lateLazy).not.toHaveBeenCalled();
  });

  it("drops a queued load that is released before it starts", () => {
    const started = Array.from({ length: 5 }, () => vi.fn());
    const releases = started.map((start) => acquireImageSlot(start));

    // The fifth is still waiting; releasing it must not consume a slot later.
    releases[4]?.();
    expect(imageLoadQueueDepth()).toEqual({ active: 4, waiting: 0, priorityWaiting: 0 });

    releases[0]?.();
    expect(started[4]).not.toHaveBeenCalled();
    expect(imageLoadQueueDepth()).toEqual({ active: 3, waiting: 0, priorityWaiting: 0 });
  });

  it("ignores repeated releases", () => {
    const start = vi.fn();
    const release = acquireImageSlot(start);
    release();
    release();
    release();
    expect(imageLoadQueueDepth()).toEqual({ active: 0, waiting: 0, priorityWaiting: 0 });
  });
});
