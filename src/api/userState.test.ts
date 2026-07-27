import { describe, expect, it, vi } from "vitest";
import { setFavorite, setWatchlist, setWatched } from "./userState";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("userState", () => {
  it("favorites use PUT/DELETE", async () => {
    const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(_url)).toContain("/api/v1/favorites/tt%2F1");
      expect(init?.method).toBe("PUT");
      return new Response(null, { status: 204 });
    });
    await setFavorite(session, "tt/1", true, fetchImpl);

    const remove = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await setFavorite(session, "tt/1", false, remove);
  });

  it("watchlist uses PUT/DELETE", async () => {
    const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(_url)).toContain("/api/v1/watchlist/show-1");
      expect(init?.method).toBe("PUT");
      return new Response(null, { status: 204 });
    });
    await setWatchlist(session, "show-1", true, fetchImpl);
  });

  it("watched uses POST/DELETE", async () => {
    const mark = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(_url)).toContain("/api/v1/watched/movie-1");
      expect(init?.method).toBe("POST");
      return new Response(null, { status: 204 });
    });
    await setWatched(session, "movie-1", true, mark);

    const clear = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await setWatched(session, "movie-1", false, clear);
  });
});
