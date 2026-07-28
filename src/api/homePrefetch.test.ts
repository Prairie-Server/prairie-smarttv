import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  resetHomePrefetchForTests,
  startHomePrefetch,
  takeHomePrefetch,
} from "./homePrefetch";
import type { PrairieSession } from "../storage/session";

vi.mock("./home", () => ({
  fetchHomeSections: vi.fn(),
}));

import { fetchHomeSections } from "./home";

const session: PrairieSession = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  username: "user",
  profileId: "p1",
};

beforeEach(() => {
  resetHomePrefetchForTests();
  vi.mocked(fetchHomeSections).mockReset();
});

describe("homePrefetch", () => {
  it("starts a prefetch and hands it off once for the same scope", async () => {
    const sections = [{ id: "1", section_type: "recent", title: "Recent", items: [] }];
    vi.mocked(fetchHomeSections).mockResolvedValue(sections);

    startHomePrefetch(session);
    expect(fetchHomeSections).toHaveBeenCalledTimes(1);

    const handoff = takeHomePrefetch(session.serverUrl, session.profileId);
    expect(handoff).not.toBeNull();
    await expect(handoff).resolves.toEqual(sections);
    expect(takeHomePrefetch(session.serverUrl, session.profileId)).toBeNull();
  });

  it("ignores duplicate starts for the same scope", () => {
    vi.mocked(fetchHomeSections).mockResolvedValue([]);
    startHomePrefetch(session);
    startHomePrefetch(session);
    expect(fetchHomeSections).toHaveBeenCalledTimes(1);
  });

  it("returns null when scope does not match", () => {
    vi.mocked(fetchHomeSections).mockResolvedValue([]);
    startHomePrefetch(session);
    expect(takeHomePrefetch("https://other.example", session.profileId)).toBeNull();
    expect(takeHomePrefetch(session.serverUrl, "other-profile")).toBeNull();
  });

  it("returns null when nothing was started", () => {
    expect(takeHomePrefetch(session.serverUrl, session.profileId)).toBeNull();
  });

  it("resolves null when the prefetch fails", async () => {
    vi.mocked(fetchHomeSections).mockRejectedValue(new Error("network"));
    startHomePrefetch(session);
    const handoff = takeHomePrefetch(session.serverUrl, session.profileId);
    await expect(handoff).resolves.toBeNull();
  });

  it("scopes keys with an omitted profile id", async () => {
    vi.mocked(fetchHomeSections).mockResolvedValue([]);
    const bare = { ...session, profileId: undefined as unknown as string };
    startHomePrefetch(bare);
    expect(takeHomePrefetch(session.serverUrl, undefined)).not.toBeNull();
    expect(takeHomePrefetch(session.serverUrl, "p1")).toBeNull();
  });
});
