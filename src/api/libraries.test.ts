import { describe, expect, it, vi } from "vitest";
import { fetchLibraries } from "./libraries";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("fetchLibraries", () => {
  it("accepts a bare array response", async () => {
    const fetchImpl = vi.fn(async () =>
      new Response(JSON.stringify([{ id: 1, name: "Movies", type: "movies" }]), {
        status: 200,
      }),
    );
    await expect(fetchLibraries(session, fetchImpl)).resolves.toEqual([
      { id: 1, name: "Movies", type: "movies" },
    ]);
  });

  it("accepts an envelope and defaults missing libraries", async () => {
    const envelope = vi.fn(async () =>
      new Response(
        JSON.stringify({ libraries: [{ id: 2, name: "Shows", type: "tv" }] }),
        { status: 200 },
      ),
    );
    await expect(fetchLibraries(session, envelope)).resolves.toEqual([
      { id: 2, name: "Shows", type: "tv" },
    ]);

    const empty = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchLibraries(session, empty)).resolves.toEqual([]);
  });
});
