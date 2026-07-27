import { describe, expect, it, vi } from "vitest";
import { fetchSimilarItems } from "./recommendations";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("fetchSimilarItems", () => {
  it("returns similar item refs", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/recommendations/similar/movie-1");
      return new Response(JSON.stringify({ items: [{ media_item_id: "movie-2", score: 0.9 }] }), {
        status: 200,
      });
    });
    await expect(fetchSimilarItems(session, "movie-1", fetchImpl)).resolves.toEqual([
      { media_item_id: "movie-2", score: 0.9 },
    ]);
  });

  it("normalizes missing items", async () => {
    const fetchImpl = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchSimilarItems(session, "movie-1", fetchImpl)).resolves.toEqual([]);
  });
});
