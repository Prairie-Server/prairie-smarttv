import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ItemDetail } from "../api/catalog";
import type { PrairieSession } from "../storage/session";
import type { PlayerLaunch } from "./PlayerScreen";

const session: PrairieSession = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  username: "user",
  profileId: "p1",
};

let detailDelay = 0;
let detailOverrides: Partial<ItemDetail> = {};
let episodeCount = 0;
let seasonsDelay = 0;
const fetchWatchDetail = vi.fn(async (_session: unknown, id: string) => ({
  content_id: id,
  type: "movie",
  title: `Watch ${id}`,
  versions: [{ file_id: 99, resolution: "1080p" }],
}));

function movie(id: string): ItemDetail {
  return {
    content_id: id,
    type: "movie",
    title: `Movie ${id}`,
    year: 2020,
    runtime: 118,
    genres: ["Action"],
    overview: "An overview.",
    poster_url: "/artwork/library/1/poster/original.rev.webp",
    backdrop_url: "/artwork/library/1/backdrop/original.rev.webp",
    cast: [{ name: "Someone", character: "Hero", photo_url: "/artwork/p/photo.webp" }],
    crew: [{ name: "Director Person", job: "Director" }],
    versions: [{ file_id: 9, resolution: "1080p" }],
    user_state: { played: false, is_favorite: false, in_watchlist: false },
    ...detailOverrides,
  } as ItemDetail;
}

vi.mock("../api/catalog", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/catalog")>();
  return {
    ...actual,
    fetchItemDetail: vi.fn(async (_session: unknown, id: string) => {
      if (detailDelay > 0) await new Promise((resolve) => setTimeout(resolve, detailDelay));
      return movie(id);
    }),
    fetchSeasons: vi.fn(async () => {
      if (seasonsDelay > 0) await new Promise((resolve) => setTimeout(resolve, seasonsDelay));
      if (episodeCount <= 0) return [];
      return [{ season_number: 1, episode_count: episodeCount, title: "Season 1" }];
    }),
    fetchEpisodes: vi.fn(async () =>
      Array.from({ length: episodeCount }, (_, i) => ({
        content_id: `e${i + 1}`,
        title: `Episode ${i + 1}`,
        season_number: 1,
        episode_number: i + 1,
        still_url: `/artwork/still/${i + 1}.webp`,
      })),
    ),
  };
});

vi.mock("../api/watch", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/watch")>();
  return {
    ...actual,
    fetchWatchDetail: (session: unknown, id: string) => fetchWatchDetail(session, id),
  };
});

vi.mock("../api/recommendations", () => ({
  fetchSimilarItems: vi.fn(async () => ({
    refs: [{ media_item_id: "s1" }, { media_item_id: "s2" }],
    cards: [
      { content_id: "s1", type: "movie", title: "Similar 1", year: 2019 },
      { content_id: "s2", type: "movie", title: "Similar 2", year: 2020 },
    ],
  })),
}));

let container: HTMLDivElement;
let root: Root | null = null;
const uncaught: unknown[] = [];
let lastPlay: PlayerLaunch | null = null;

async function renderScreen(contentId = "m1") {
  const { ItemDetailScreen } = await import("./ItemDetailScreen");
  const { ServerUrlContext } = await import("../serverUrlContext");
  await act(async () => {
    root = createRoot(container, {
      onUncaughtError: (error) => uncaught.push(error),
      onCaughtError: (error) => uncaught.push(error),
    });
    root.render(
      <ServerUrlContext.Provider value={session.serverUrl}>
        <ItemDetailScreen
          session={session}
          contentId={contentId}
          onBack={() => {}}
          onPlay={(launch) => {
            lastPlay = launch;
          }}
          onOpenItem={() => {}}
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

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  uncaught.length = 0;
  detailDelay = 0;
  detailOverrides = {};
  episodeCount = 0;
  seasonsDelay = 0;
  lastPlay = null;
  fetchWatchDetail.mockClear();
});

afterEach(() => {
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
});

describe("ItemDetailScreen", () => {
  it("renders the hero and similar row without throwing", async () => {
    await renderScreen();
    await settle();
    expect(uncaught).toEqual([]);
    expect(container.textContent).toContain("Movie m1");
    expect(container.textContent).toContain("More Like This");
  });

  it("focuses Back while the hero is still loading, then Play", async () => {
    detailDelay = 20;
    await renderScreen();
    // Nothing but Back exists yet — a bare OK press must not land on <body>.
    expect(container.textContent).toContain("Loading…");
    expect(document.activeElement).toBe(container.querySelector(".detail-back"));

    await settle(40);
    expect(document.activeElement).toBe(container.querySelector(".focus-btn--primary"));
  });

  it("survives sparse payloads that previously killed the render", async () => {
    detailOverrides = {
      type: undefined as unknown as string,
      crew: [{ name: "No Job" } as unknown as NonNullable<ItemDetail["crew"]>[number]],
      cast: [{ character: "Unnamed" } as unknown as NonNullable<ItemDetail["cast"]>[number]],
      genres: undefined,
      versions: undefined,
    };
    await renderScreen();
    await settle();
    expect(uncaught).toEqual([]);
    expect(container.querySelector(".detail-screen")).not.toBeNull();
  });

  it("loads only the backdrop eagerly and keeps poster/logo off the critical path", async () => {
    detailOverrides = {
      logo_url: "/artwork/library/1/logo/original.rev.webp",
      backdrop_avif_url: "/artwork/library/1/backdrop/original.rev.avif",
      poster_avif_url: "/artwork/library/1/poster/original.rev.avif",
    };
    await renderScreen();
    await settle();
    const hero = container.querySelector<HTMLImageElement>(".detail-hero__art img");
    expect(hero?.getAttribute("loading")).toBe("eager");
    expect(hero?.getAttribute("src") ?? "").not.toMatch(/\.avif/i);
    // Poster/logo wait for the backdrop so their decode cannot lock D-pad nav.
    expect(container.querySelector(".detail-hero__poster img")).toBeNull();
    expect(container.querySelector(".detail-hero__logo img")).toBeNull();
    expect(container.textContent).toContain("Movie m1");
  });

  it("admits poster and logo after the backdrop loads", async () => {
    detailOverrides = {
      logo_url: "/artwork/library/1/logo/original.rev.webp",
    };
    await renderScreen();
    await settle();
    const hero = container.querySelector<HTMLImageElement>(".detail-hero__art img");
    expect(hero).not.toBeNull();
    await act(async () => {
      hero?.dispatchEvent(new Event("load"));
    });
    await settle();
    expect(container.querySelector(".detail-hero__poster img")).not.toBeNull();
    expect(container.querySelector(".detail-hero__logo img")).not.toBeNull();
  });

  it("plays from item-detail versions without a watch round-trip", async () => {
    await renderScreen();
    await settle();
    const play = container.querySelector<HTMLButtonElement>(".focus-btn--primary");
    expect(play).not.toBeNull();
    await act(async () => {
      play?.click();
    });
    expect(lastPlay?.fileId).toBe(9);
    expect(fetchWatchDetail).not.toHaveBeenCalled();
  });

  it("shows series Play immediately and only mounts a page of episodes", async () => {
    detailOverrides = { type: "series", title: "Series s1", versions: [] };
    episodeCount = 20;
    await renderScreen("s1");
    await settle();

    // Play exists as soon as the hero is up — not gated on the episode list.
    expect(container.querySelector(".focus-btn--primary")).not.toBeNull();
    await settle(20);
    expect(container.querySelectorAll(".episode-card").length).toBe(8);
    expect(container.textContent).toContain("More episodes");
    // Episode stills wait for the hero grace so they cannot contend with backdrop.
    expect(container.querySelectorAll(".episode-card__still img").length).toBe(0);
    await settle(950);
    expect(container.querySelectorAll(".episode-card__still img").length).toBeGreaterThan(0);
  });

  it("defers cast photos until the hero grace period elapses", async () => {
    await renderScreen();
    await settle();
    expect(container.querySelector(".cast-rail")).toBeNull();
    await settle(950);
    expect(container.querySelector(".cast-rail")).not.toBeNull();
  });
});
