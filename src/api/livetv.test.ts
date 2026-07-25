import { describe, expect, it, vi } from "vitest";
import {
  channelDisplayLabel,
  currentProgramForChannel,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  nextProgramForChannel,
  playableLiveUrl,
  releaseLiveTvSession,
  startLiveTvSession,
  type LiveTvChannel,
  type LiveTvProgram,
} from "./livetv";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

const channel: LiveTvChannel = {
  id: "ch-1",
  tuner_id: "t1",
  number: "4.1",
  callsign: "KTV",
  name: "Prairie Local",
  hd: true,
  enabled: true,
};

describe("playableLiveUrl", () => {
  it("prefers hls_url then stream_url", () => {
    expect(playableLiveUrl({ session_id: "s", hls_url: "/hls" })).toBe("/hls");
    expect(playableLiveUrl({ session_id: "s", stream_url: "/raw" })).toBe("/raw");
    expect(playableLiveUrl({ session_id: "s" })).toBeNull();
  });
});

describe("channelDisplayLabel", () => {
  it("uses name, callsign, then channel number", () => {
    expect(channelDisplayLabel(channel)).toBe("Prairie Local");
    expect(
      channelDisplayLabel({ ...channel, name: "", callsign: "KTV" }),
    ).toBe("KTV");
    expect(
      channelDisplayLabel({ ...channel, name: "", callsign: "", number: "7" }),
    ).toBe("Channel 7");
  });
});

describe("guide helpers", () => {
  const programs: LiveTvProgram[] = [
    {
      id: "p0",
      channel_id: "ch-1",
      start: "2026-07-25T18:00:00.000Z",
      stop: "2026-07-25T19:00:00.000Z",
      title: "Earlier",
    },
    {
      id: "p1",
      channel_id: "ch-1",
      start: "2026-07-25T19:00:00.000Z",
      stop: "2026-07-25T20:00:00.000Z",
      title: "Now Show",
    },
    {
      id: "p2",
      channel_id: "ch-1",
      start: "2026-07-25T20:00:00.000Z",
      stop: "2026-07-25T21:00:00.000Z",
      title: "Next Show",
    },
    {
      id: "other",
      channel_id: "ch-2",
      start: "2026-07-25T19:00:00.000Z",
      stop: "2026-07-25T20:00:00.000Z",
      title: "Other",
    },
  ];
  const now = Date.parse("2026-07-25T19:30:00.000Z");

  it("picks current and next programs for a channel", () => {
    expect(currentProgramForChannel(programs, "ch-1", now)?.title).toBe("Now Show");
    expect(nextProgramForChannel(programs, "ch-1", now)?.title).toBe("Next Show");
    expect(currentProgramForChannel(programs, "missing", now)).toBeNull();
  });
});

describe("Live TV API", () => {
  it("lists enabled channels and treats 404 as empty", async () => {
    const ok = vi.fn(async () =>
      new Response(
        JSON.stringify({
          channels: [
            channel,
            { ...channel, id: "off", enabled: false },
          ],
        }),
        { status: 200 },
      ),
    );
    const list = await fetchLiveTvChannels(session, ok);
    expect(list).toHaveLength(1);
    expect(list[0]?.id).toBe("ch-1");

    const missing = vi.fn(async () => new Response("nope", { status: 404 }));
    await expect(fetchLiveTvChannels(session, missing)).resolves.toEqual([]);
  });

  it("loads guide, starts, and releases sessions", async () => {
    const guideFetch = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/livetv/guide?channels=ch-1");
      return new Response(JSON.stringify({ programs: [] }), { status: 200 });
    });
    await expect(fetchLiveTvGuide(session, ["ch-1"], guideFetch)).resolves.toEqual([]);
    await expect(fetchLiveTvGuide(session, [])).resolves.toEqual([]);

    const startFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/channels/ch-1/session");
      expect(init?.method).toBe("POST");
      return new Response(
        JSON.stringify({ session_id: "live-1", hls_url: "/live.m3u8" }),
        { status: 200 },
      );
    });
    const started = await startLiveTvSession(session, "ch-1", startFetch);
    expect(started.session_id).toBe("live-1");

    const releaseFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/sessions/live-1");
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await releaseLiveTvSession(session, "live-1", releaseFetch);
    expect(releaseFetch).toHaveBeenCalledOnce();
  });
});
