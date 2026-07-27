import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { HomeSection } from "../api/home";
import type { PrairieSession } from "../storage/session";

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
      return sections;
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

async function flushFrames(count = 1) {
  for (let frame = 0; frame < count; frame++) {
    const pending = frameQueue;
    frameQueue = [];
    await act(async () => {
      for (const callback of pending) callback(performance.now());
    });
  }
}

async function renderHome(options: { showOnNow?: boolean } = {}) {
  const { HomeBrowseScreen } = await import("./HomeBrowseScreen");
  const { ServerUrlContext } = await import("../serverUrlContext");
  await act(async () => {
    root = createRoot(container);
    root.render(
      <ServerUrlContext.Provider value={session.serverUrl}>
        <HomeBrowseScreen
          session={session}
          onOpenItem={() => {}}
          onOpenLiveChannel={options.showOnNow ? () => {} : undefined}
          showOnNow={options.showOnNow ?? false}
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
  releaseChannels = null;
  channelCount = 4;
  frameQueue = [];
  realRaf = window.requestAnimationFrame;
  window.requestAnimationFrame = ((callback: FrameRequestCallback) => {
    frameQueue.push(callback);
    return frameQueue.length;
  }) as typeof window.requestAnimationFrame;
});

afterEach(() => {
  window.requestAnimationFrame = realRaf;
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
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

  it("defers below-the-fold rows, then mounts them with reserved height", async () => {
    await renderHome();
    await settle();

    const deferred = container.querySelectorAll(".media-row--deferred");
    expect(deferred.length).toBe(sections.length - 2);
    expect(rowScrollers()).toBe(2);
    // Deferred rows hold a height so mounting them cannot reflow rows above.
    expect((deferred[0] as HTMLElement).style.minHeight).not.toBe("");

    // Frames pass: the rest mount a chunk at a time.
    await flushFrames(1);
    expect(rowScrollers()).toBe(4);
    await flushFrames(5);
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
});

describe("HomeBrowseScreen entry focus", () => {
  it("focuses the first row when there is no On now row", async () => {
    await renderHome();
    await settle();
    const first = container.querySelector<HTMLElement>(".media-row__scroller [data-focus-index]");
    expect(document.activeElement).toBe(first);
  });

  it("focuses the On now row when it is the topmost row", async () => {
    await renderHome({ showOnNow: true });
    await settle();
    const onNowCard = container.querySelector<HTMLElement>(".media-row--on-now [data-focus-index]");
    expect(onNowCard).not.toBeNull();
    expect(document.activeElement).toBe(onNowCard);
  });

  it("holds a same-height On now slot while the guide loads", async () => {
    releaseChannels = () => {};
    await renderHome({ showOnNow: true });
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
    await settle(20);
    expect(container.querySelector(".media-row--on-now")).toBeNull();
    const first = container.querySelector<HTMLElement>(".media-row__scroller [data-focus-index]");
    expect(document.activeElement).toBe(first);
  });
});
