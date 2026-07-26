import { describe, expect, it, vi } from "vitest";
import { fetchHomeSections } from "./home";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("fetchHomeSections", () => {
  it("normalizes missing sections and item arrays", async () => {
    const empty = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(fetchHomeSections(session, empty)).resolves.toEqual([]);

    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            sections: [
              { id: "1", section_type: "continue_watching", title: "Continue Watching" },
              {
                id: "2",
                section_type: "recently_added",
                title: "Recently Added",
                items: [{ content_id: "m1", type: "movie", title: "Dune" }],
              },
            ],
          }),
          { status: 200 },
        ),
    );

    const sections = await fetchHomeSections(session, fetchImpl);
    expect(sections[0]?.items).toEqual([]);
    expect(sections[1]?.items).toHaveLength(1);
  });
});
