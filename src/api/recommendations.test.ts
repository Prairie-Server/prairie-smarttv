import { describe, expect, it, vi } from "vitest";
import { fetchSimilarItems } from "./recommendations";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

function jsonResponse(body: unknown) {
  return new Response(JSON.stringify(body), { status: 200 });
}

describe("fetchSimilarItems", () => {
  it("returns scored refs and hydrated cards", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/recommendations/similar/movie-1");
      return jsonResponse({
        items: [{ media_item_id: "movie-2", score: 0.9 }],
        cards: [{ content_id: "movie-2", type: "movie", title: "Movie 2", year: 2021 }],
      });
    });

    await expect(fetchSimilarItems(session, "movie-1", fetchImpl)).resolves.toEqual({
      refs: [{ media_item_id: "movie-2", score: 0.9 }],
      cards: [{ content_id: "movie-2", type: "movie", title: "Movie 2", year: 2021 }],
    });
  });

  it("returns refs with no cards against a server that does not hydrate", async () => {
    // Callers then fall back to one item-detail request per ref.
    const fetchImpl = vi.fn(async () =>
      jsonResponse({ items: [{ media_item_id: "movie-2", score: 0.4 }] }),
    );
    await expect(fetchSimilarItems(session, "movie-1", fetchImpl)).resolves.toEqual({
      refs: [{ media_item_id: "movie-2", score: 0.4 }],
      cards: [],
    });
  });

  it("drops malformed cards and normalizes missing fields", async () => {
    const fetchImpl = vi.fn(async () =>
      jsonResponse({
        cards: [{ content_id: "ok", type: "movie", title: "Ok" }, { title: "no id" }, null],
      }),
    );
    await expect(fetchSimilarItems(session, "movie-1", fetchImpl)).resolves.toEqual({
      refs: [],
      cards: [{ content_id: "ok", type: "movie", title: "Ok" }],
    });

    const empty = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchSimilarItems(session, "movie-1", empty)).resolves.toEqual({
      refs: [],
      cards: [],
    });
  });
});
