import { describe, expect, it, vi } from "vitest";
import { fetchCatalog, fetchEpisodes, fetchItemDetail, fetchSeasons } from "./catalog";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
  profileToken: "pin",
};

describe("fetchCatalog", () => {
  it("builds query params and normalizes missing items", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const parsed = new URL(String(url));
      expect(parsed.pathname).toBe("/api/v1/catalog");
      expect(parsed.searchParams.get("library_id")).toBe("3");
      expect(parsed.searchParams.get("q")).toBe("dune");
      expect(parsed.searchParams.get("source")).toBe("library_collection");
      expect(parsed.searchParams.get("collection_id")).toBe("c1");
      expect(parsed.searchParams.get("offset")).toBe("20");
      expect(parsed.searchParams.get("limit")).toBe("40");
      expect(parsed.searchParams.get("snapshot")).toBe("snap");
      expect(parsed.searchParams.get("sort")).toBe("title");
      expect(parsed.searchParams.get("order")).toBe("asc");
      expect(parsed.searchParams.get("type")).toBe("movie");
      expect(new Headers(init?.headers).get("X-Profile-Id")).toBe("profile-1");
      expect(new Headers(init?.headers).get("X-Profile-Token")).toBe("pin");
      return new Response(JSON.stringify({ has_more: true }), { status: 200 });
    });

    const page = await fetchCatalog(
      session,
      {
        libraryId: 3,
        type: "movie",
        q: "dune",
        source: "library_collection",
        collectionId: "c1",
        offset: 20,
        limit: 40,
        snapshot: "snap",
        sort: "title",
        order: "asc",
      },
      fetchImpl,
    );
    expect(page.items).toEqual([]);
    expect(page.has_more).toBe(true);
  });

  it("requests the bare catalog path with defaults", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toBe("https://prairie.example/api/v1/catalog");
      return new Response(
        JSON.stringify({ items: [{ content_id: "1", type: "movie", title: "A" }] }),
        {
          status: 200,
        },
      );
    });
    const page = await fetchCatalog(session, {}, fetchImpl);
    expect(page.items).toHaveLength(1);
  });
});

describe("catalog detail helpers", () => {
  it("fetches item detail", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/catalog/items/tt%2F1");
      return new Response(JSON.stringify({ content_id: "tt/1", type: "movie", title: "Dune" }), {
        status: 200,
      });
    });
    await expect(fetchItemDetail(session, "tt/1", fetchImpl)).resolves.toMatchObject({
      title: "Dune",
    });
  });

  it("accepts seasons as a bare array or envelope", async () => {
    const arrayFetch = vi.fn(
      async () => new Response(JSON.stringify([{ season_number: 1 }]), { status: 200 }),
    );
    await expect(fetchSeasons(session, "show-1", arrayFetch)).resolves.toEqual([
      { season_number: 1 },
    ]);

    const envelopeFetch = vi.fn(
      async () =>
        new Response(JSON.stringify({ seasons: [{ season_number: 2 }] }), { status: 200 }),
    );
    await expect(fetchSeasons(session, "show-1", envelopeFetch)).resolves.toEqual([
      { season_number: 2 },
    ]);

    const emptyFetch = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchSeasons(session, "show-1", emptyFetch)).resolves.toEqual([]);
  });

  it("accepts episodes as a bare array or envelope", async () => {
    const arrayFetch = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/seasons/1/episodes");
      return new Response(JSON.stringify([{ content_id: "e1", title: "Pilot" }]), { status: 200 });
    });
    await expect(fetchEpisodes(session, "show-1", 1, arrayFetch)).resolves.toEqual([
      { content_id: "e1", title: "Pilot" },
    ]);

    const envelopeFetch = vi.fn(
      async () =>
        new Response(JSON.stringify({ episodes: [{ content_id: "e2", title: "Two" }] }), {
          status: 200,
        }),
    );
    await expect(fetchEpisodes(session, "show-1", 1, envelopeFetch)).resolves.toEqual([
      { content_id: "e2", title: "Two" },
    ]);

    const emptyFetch = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchEpisodes(session, "show-1", 1, emptyFetch)).resolves.toEqual([]);
  });
});
