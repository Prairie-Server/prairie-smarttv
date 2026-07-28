import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { HomeSection } from "../api/home";
import { saveCachedHomeSections } from "../lib/homeSectionsCache";
import type { PrairieSession } from "../storage/session";
import { homeSectionsSignature, reconcileMountedRows } from "./HomeBrowseScreen";

const session: PrairieSession = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  username: "user",
  profileId: "p1",
};

let homeDelay = 0;
let channelCount = 4;
/** Resolved by the test to release the Live TV channel request. */
let releaseChannels: (() => void) | null = null;
/** Optional override so a refresh can return different rows than the first paint. */
let homeSectionsOverride: HomeSection[] | null = null;

function item(prefix: string, index: number) {
  return {
    content_id: `${prefix}-${index}`,
    type: "movie",
    title: `${prefix} ${index}`,
    year: 2020,
    poster_url: "/artwork/library/1/poster/original.rev.webp",
  };
}

const sections: HomeSection[] = Array.from({ length: 8 }, (_, rowIndex) => ({
  id: `row-${rowIndex}`,
  title: `Row ${rowIndex}`,
  section_type: "recent",
  items: Array.from({ length: 12 }, (_, i) => item(`R${rowIndex}`, i)),
})) as unknown as HomeSection[];

vi.mock("../api/home", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/home")>();
  return {
    ...actual,
    fetchHomeSections: vi.fn(async () => {
      if (homeDelay > 0) await new Promise((resolve) => setTimeout(resolve, homeDelay));
      return homeSectionsOverride ?? sections;
    }),
  };
});

vi.mock("../api/livetv", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/livetv")>();
  return {
    ...actual,
    fetchLiveTvChannels: vi.fn(async () => {
      if (releaseChannels) {
        await new Promise<void>((resolve) => {
          const previous = releaseChannels;
          releaseChannels = () => {
            previous?.();
            resolve();
          };
        });
      }
      return Array.from({ length: channelCount }, (_, i) => ({
        id: `ch${i}`,
        name: `Channel ${i}`,
        enabled: true,
      }));
    }),
    fetchLiveTvGuide: vi.fn(async () =>
      Array.from({ length: channelCount }, (_, i) => ({
        channel_id: `ch${i}`,
        title: `Programme ${i}`,
        start: new Date(Date.now() - 60_000).toISOString(),
        stop: new Date(Date.now() + 60_000).toISOString(),
      })),
    ),
  };
});

let container: HTMLDivElement;
let root: Root | null = null;
let frameQueue: FrameRequestCallback[] = [];
let realRaf: typeof window.requestAnimationFrame;
let realIntersectionObserver: typeof window.IntersectionObserver | undefined;
let observedSlots: HTMLElement[] = [];
let intersectionCallbacks: IntersectionObserverCallback[] = [];

/** Report the given deferred slots as scrolled into view. */
async function scrollSlotsIntoView(slots: HTMLElement[]) {
  const entries = slots.map(
    (target) => ({ target, isIntersecting: true }) as unknown as IntersectionObserverEntry,
  );
  await act(async () => {
    for (const callback of intersectionCallbacks) {
      callback(entries, {} as IntersectionObserver);
    }
  });
}

async function flushFrames(count = 1) {
  for (let frame = 0; frame < count; frame++) {
    const pending = frameQueue;
    frameQueue = [];
    await act(async () => {
      for (const callback of pending) callback(performance.now());
    });
  }
}

async function renderHome(options: { showOnNow?: boolean; reserveOnNow?: boolean } = {}) {
  const { HomeBrowseScreen } = await import("./HomeBrowseScreen");
  const { ServerUrlContext } = await import("../serverUrlContext");
  const wantsOnNow = Boolean(options.showOnNow || options.reserveOnNow);
  await act(async () => {
    root = createRoot(container);
    root.render(
      <ServerUrlContext.Provider value={session.serverUrl}>
        <HomeBrowseScreen
          session={session}
          onOpenItem={() => {}}
          onOpenLiveChannel={wantsOnNow ? () => {} : undefined}
          showOnNow={options.showOnNow ?? false}
          reserveOnNow={options.reserveOnNow ?? false}
        />
      </ServerUrlContext.Provider>,
    );
  });
}

async function settle(ms = 0) {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, ms));
  });
}

function rowScrollers(): number {
  return container.querySelectorAll(".media-row__scroller").length;
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  homeDelay = 0;
  homeSectionsOverride = null;
  releaseChannels = null;
  channelCount = 4;
  frameQueue = [];
  observedSlots = [];
  intersectionCallbacks = [];
  localStorage.clear();
  realIntersectionObserver = window.IntersectionObserver;
  class TestIntersectionObserver {
    constructor(callback: IntersectionObserverCallback) {
      intersectionCallbacks.push(callback);
    }
    observe(target: Element) {
      observedSlots.push(target as HTMLElement);
    }
    unobserve() {}
    disconnect() {}
    takeRecords(): IntersectionObserverEntry[] {
      return [];
    }
  }
  window.IntersectionObserver =
    TestIntersectionObserver as unknown as typeof window.IntersectionObserver;
  realRaf = window.requestAnimationFrame;
  window.requestAnimationFrame = ((callback: FrameRequestCallback) => {
    frameQueue.push(callback);
    return frameQueue.length;
  }) as typeof window.requestAnimationFrame;
});

afterEach(() => {
  window.requestAnimationFrame = realRaf;
  if (realIntersectionObserver) window.IntersectionObserver = realIntersectionObserver;
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
});

describe("reconcileMountedRows", () => {
  it("keeps scrolled-in rows when a refresh arrives", () => {
    const prev = new Set([0, 1, 2, 4]);
    const next = reconcileMountedRows(prev, 8);
    expect([...next].sort((a, b) => a - b)).toEqual([0, 1, 2, 4]);
  });

  it("prunes indices past the new row count", () => {
    const prev = new Set([0, 1, 5, 7]);
    const next = reconcileMountedRows(prev, 3);
    expect([...next].sort((a, b) => a - b)).toEqual([0, 1]);
  });
});

describe("homeSectionsSignature", () => {
  it("changes when continue-watching progress changes", () => {
    const base = sections[0]!;
    const a = [{ ...base, items: [{ ...base.items[0]!, position_seconds: 10 }] }];
    const b = [{ ...base, items: [{ ...base.items[0]!, position_seconds: 40 }] }];
    expect(homeSectionsSignature(a)).not.toBe(homeSectionsSignature(b));
  });
});

describe("HomeBrowseScreen first paint", () => {
  it("paints skeleton rows before any data arrives", async () => {
    homeDelay = 50;
    await renderHome();
    // First commit must not wait on the sections request.
    expect(container.querySelectorAll(".media-row--skeleton").length).toBeGreaterThan(0);
    expect(container.querySelector(".home-hero--skeleton")).not.toBeNull();
    await settle(80);
  });

  it("keeps below-the-fold rows unmounted until their slot nears the viewport", async () => {
    await renderHome();
    await settle();

    const deferred = [...container.querySelectorAll<HTMLElement>(".media-row--deferred")];
    // Only the first row is mounted; the rest are reserved slots. Mounting every
    // row put >300 cards on screen at 4K/8K ui-scale.
    expect(deferred.length).toBe(sections.length - 1);
    expect(rowScrollers()).toBe(1);
    // Deferred rows hold a height so mounting them cannot reflow rows above.
    expect(deferred[0]?.style.minHeight).not.toBe("");
    expect(observedSlots.length).toBe(deferred.length);

    // Scrolling brings the next two slots close enough to mount.
    await scrollSlotsIntoView(deferred.slice(0, 2));
    expect(rowScrollers()).toBe(3);
    expect(container.querySelectorAll(".media-row--deferred").length).toBe(sections.length - 3);

    // Rows further down stay unmounted.
    expect(rowScrollers()).toBeLessThan(sections.length);
  });

  it("mounts rows a chunk per frame when IntersectionObserver is unavailable", async () => {
    // Older TV browsers without IO must still reach every row.
    (window as { IntersectionObserver?: unknown }).IntersectionObserver = undefined;
    await renderHome();
    await settle();
    expect(rowScrollers()).toBe(1);
    for (let frame = 0; frame < 8; frame++) await flushFrames(1);
    expect(container.querySelectorAll(".media-row--deferred").length).toBe(0);
    expect(rowScrollers()).toBe(sections.length);
  });

  it("keeps eager image decoding to a small first-row budget", async () => {
    await renderHome();
    await settle();
    const eager = [...container.querySelectorAll("img")].filter(
      (img) => img.getAttribute("loading") === "eager",
    );
    expect(eager.length).toBeGreaterThan(0);
    expect(eager.length).toBeLessThanOrEqual(4);
  });

  it("does not collapse scrolled-in rows when the network refresh lands", async () => {
    // Seed a warm cache so Home paints immediately, then delay the refresh.
    saveCachedHomeSections(sections, session.serverUrl, session.profileId);
    homeDelay = 80;
    // Refresh returns slightly newer progress so setSections actually runs.
    homeSectionsOverride = sections.map((section, rowIndex) =>
      rowIndex === 0
        ? {
            ...section,
            items: section.items.map((entry, i) =>
              i === 0 ? { ...entry, position_seconds: 120 } : entry,
            ),
          }
        : section,
    );

    await renderHome();
    await settle();

    const deferred = [...container.querySelectorAll<HTMLElement>(".media-row--deferred")];
    expect(deferred.length).toBeGreaterThan(0);
    await scrollSlotsIntoView(deferred.slice(0, 2));
    const mountedBefore = rowScrollers();
    expect(mountedBefore).toBeGreaterThan(1);

    const focused = container.querySelectorAll<HTMLElement>("[data-focus-index]")[3];
    expect(focused).toBeTruthy();
    await act(async () => {
      focused!.focus();
    });
    expect(document.activeElement).toBe(focused);

    await settle(100);

    // Refresh must not tear down rows the user already reached.
    expect(rowScrollers()).toBeGreaterThanOrEqual(mountedBefore);
    expect(document.activeElement).toBe(focused);
  });
});

describe("HomeBrowseScreen entry focus", () => {
  it("focuses the first row when there is no On now row", async () => {
    await renderHome();
    await settle();
    const first = container.querySelector<HTMLElement>(".media-row__scroller [data-focus-index]");
    expect(document.activeElement).toBe(first);
  });

  it("keeps entry focus on the first home row while On now stays below the fold", async () => {
    await renderHome({ showOnNow: true });
    await settle();
    const first = container.querySelector<HTMLElement>(".media-row__scroller [data-focus-index]");
    expect(document.activeElement).toBe(first);
    expect(container.querySelector(".media-row--on-now")).toBeNull();
    expect(container.querySelector("[data-on-now]")).not.toBeNull();

    const onNowSlot = container.querySelector<HTMLElement>("[data-on-now]");
    await scrollSlotsIntoView([onNowSlot!]);
    await settle();
    // Loading On now must not steal focus from the row the user already has.
    expect(document.activeElement).toBe(first);
    expect(container.querySelector(".media-row--on-now")).not.toBeNull();
  });

  it("holds a same-height On now slot while the guide loads", async () => {
    releaseChannels = () => {};
    await renderHome({ showOnNow: true });
    await settle();

    const deferred = container.querySelector<HTMLElement>("[data-on-now]");
    expect(deferred).not.toBeNull();
    await scrollSlotsIntoView([deferred!]);
    await settle();

    const slot = container.querySelector(".media-row--on-now");
    expect(slot).not.toBeNull();
    expect(slot?.classList.contains("media-row--skeleton")).toBe(true);
    // Same component and variant as the real row, so the height is reserved.
    expect(slot?.classList.contains("media-row--poster")).toBe(true);

    await act(async () => {
      releaseChannels?.();
      await Promise.resolve();
    });
    await settle();
    const filled = container.querySelector(".media-row--on-now");
    expect(filled?.classList.contains("media-row--skeleton")).toBe(false);
    expect(container.querySelectorAll(".on-now-card").length).toBe(channelCount);
  });

  it("collapses the On now slot when the server has no channels", async () => {
    channelCount = 0;
    await renderHome({ showOnNow: true });
    await settle();
    const deferred = container.querySelector<HTMLElement>("[data-on-now]");
    expect(deferred).not.toBeNull();
    await scrollSlotsIntoView([deferred!]);
    await settle(20);
    expect(container.querySelector(".media-row--on-now")).toBeNull();
    const first = container.querySelector<HTMLElement>(".media-row__scroller [data-focus-index]");
    expect(document.activeElement).toBe(first);
  });

  it("reserves an On now deferred slot while the Live TV probe is pending", async () => {
    await renderHome({ reserveOnNow: true });
    await settle();
    // Below the fold: only a height reservation until the slot nears the viewport.
    expect(container.querySelector("[data-on-now]")).not.toBeNull();
    expect(container.querySelector(".media-row--on-now")).toBeNull();

    const deferred = container.querySelector<HTMLElement>("[data-on-now]");
    await scrollSlotsIntoView([deferred!]);
    await settle();
    const slot = container.querySelector(".media-row--on-now");
    expect(slot).not.toBeNull();
    expect(slot?.classList.contains("media-row--skeleton")).toBe(true);
    // Probe pending must not fetch the guide yet.
    expect(container.querySelectorAll(".on-now-card").length).toBe(0);
  });
});
