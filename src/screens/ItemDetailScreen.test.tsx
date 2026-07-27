import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ItemDetail } from "../api/catalog";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  username: "user",
  profileId: "p1",
};

let detailDelay = 0;
let detailOverrides: Partial<ItemDetail> = {};

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
    cast: [{ name: "Someone", character: "Hero" }],
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
    fetchSeasons: vi.fn(async () => []),
    fetchEpisodes: vi.fn(async () => []),
  };
});

vi.mock("../api/recommendations", () => ({
  fetchSimilarItems: vi.fn(async () => [{ media_item_id: "s1" }, { media_item_id: "s2" }]),
}));

let container: HTMLDivElement;
let root: Root | null = null;
const uncaught: unknown[] = [];

async function renderScreen() {
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
          contentId="m1"
          onBack={() => {}}
          onPlay={() => {}}
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
});
