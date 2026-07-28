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
  it("starts up to two loads and queues the rest", () => {
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
});
