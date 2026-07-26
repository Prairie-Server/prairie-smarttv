import { describe, expect, it, vi } from "vitest";
import { fetchLibraryCollections, fetchPersonalCollections } from "./collections";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("fetchLibraryCollections", () => {
  it("flattens grouped and ungrouped cards with library id and title fallback", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/library/9/collections");
      return new Response(
        JSON.stringify({
          groups: [
            {
              id: "g1",
              collections: [{ id: "c1", name: "Marvel", item_count: 2 }],
            },
          ],
          ungrouped: {
            collections: [{ id: "c2", title: "Standalone", item_count: 1 }],
          },
        }),
        { status: 200 },
      );
    });

    await expect(fetchLibraryCollections(session, 9, fetchImpl)).resolves.toEqual([
      { id: "c1", name: "Marvel", item_count: 2, library_id: 9, title: "Marvel" },
      { id: "c2", title: "Standalone", item_count: 1, library_id: 9 },
    ]);
  });

  it("returns an empty list when groups are missing", async () => {
    const fetchImpl = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchLibraryCollections(session, 1, fetchImpl)).resolves.toEqual([]);
  });

  it("tolerates groups/ungrouped without collection arrays", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            groups: [{ id: "g-empty" }],
            ungrouped: {},
          }),
          { status: 200 },
        ),
    );
    await expect(fetchLibraryCollections(session, 2, fetchImpl)).resolves.toEqual([]);
  });
});

describe("fetchPersonalCollections", () => {
  it("flattens top-level and grouped personal collections", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            collections: [{ id: "p1", name: "Mine" }],
            groups: [{ collections: [{ id: "p2", title: "Favorites" }] }],
          }),
          { status: 200 },
        ),
    );

    await expect(fetchPersonalCollections(session, fetchImpl)).resolves.toEqual([
      { id: "p1", name: "Mine", title: "Mine" },
      { id: "p2", title: "Favorites" },
    ]);
  });

  it("defaults missing personal collection arrays", async () => {
    const fetchImpl = vi.fn(
      async () => new Response(JSON.stringify({ groups: [{}] }), { status: 200 }),
    );
    await expect(fetchPersonalCollections(session, fetchImpl)).resolves.toEqual([]);
  });
});
