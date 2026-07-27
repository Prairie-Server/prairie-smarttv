import { describe, expect, it, vi } from "vitest";
import {
  cancelLiveTvRecording,
  channelDisplayLabel,
  currentProgramForChannel,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  fetchLiveTvRecordings,
  isWatchableHls,
  nextProgramForChannel,
  playableLiveUrl,
  releaseLiveTvSession,
  resolveLivePlaybackUrl,
  scheduleLiveTvRecording,
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
  it("prefers hls_url and honors transport=hls", () => {
    expect(playableLiveUrl({ session_id: "s", hls_url: "/hls.m3u8", transport: "hls" })).toBe(
      "/hls.m3u8",
    );
    expect(
      playableLiveUrl({
        session_id: "s",
        hls_url: "/hls.m3u8",
        stream_url: "/mpegts",
        transport: "hls",
      }),
    ).toBe("/hls.m3u8");
  });

  it("returns mpegts proxy path when transport=mpegts and no HLS is available", () => {
    expect(
      playableLiveUrl({
        session_id: "s",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
        transport: "mpegts",
      }),
    ).toBe("/api/v1/livetv/sessions/s1/stream");
  });

  it("prefers HLS over mpegts transport when hls_url is present", () => {
    expect(
      playableLiveUrl({
        session_id: "s",
        hls_url: "/api/v1/livetv/live-hls/ticket/index.m3u8",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
        transport: "mpegts",
      }),
    ).toBe("/api/v1/livetv/live-hls/ticket/index.m3u8");
  });

  it("prefers HLS-looking URLs when transport is omitted", () => {
    expect(
      playableLiveUrl({
        session_id: "s",
        hls_url: "/api/v1/livetv/live-hls/ticket/index.m3u8",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
      }),
    ).toBe("/api/v1/livetv/live-hls/ticket/index.m3u8");
    expect(
      playableLiveUrl({
        session_id: "s",
        stream_url: "/api/v1/livetv/proxy/index.m3u8",
      }),
    ).toBe("/api/v1/livetv/proxy/index.m3u8");
  });

  it("falls back to stream_url and treats blank as null", () => {
    expect(playableLiveUrl({ session_id: "s", stream_url: "/raw" })).toBe("/raw");
    expect(playableLiveUrl({ session_id: "s", hls_url: "   ", stream_url: "  " })).toBeNull();
    expect(playableLiveUrl({ session_id: "s" })).toBeNull();
  });
});

describe("isWatchableHls", () => {
  it("is false for mpegts-only streams", () => {
    expect(
      isWatchableHls({
        session_id: "s",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
        transport: "mpegts",
      }),
    ).toBe(false);
  });

  it("is true when mpegts transport includes an HLS remux URL", () => {
    expect(
      isWatchableHls({
        session_id: "s",
        hls_url: "/api/v1/livetv/live-hls/ticket/index.m3u8",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
        transport: "mpegts",
      }),
    ).toBe(true);
  });

  it("is true for hls transport with a URL", () => {
    expect(
      isWatchableHls({
        session_id: "s",
        hls_url: "/api/v1/livetv/live-hls/ticket/index.m3u8",
        transport: "hls",
      }),
    ).toBe(true);
  });

  it("infers HLS from m3u8 or live-hls paths when transport is omitted", () => {
    expect(
      isWatchableHls({
        session_id: "s",
        hls_url: "/live.m3u8",
      }),
    ).toBe(true);
    expect(
      isWatchableHls({
        session_id: "s",
        stream_url: "/api/v1/livetv/live-hls/ticket/index.m3u8",
      }),
    ).toBe(true);
    expect(
      isWatchableHls({
        session_id: "s",
        stream_url: "/api/v1/livetv/sessions/s1/stream",
      }),
    ).toBe(false);
  });
});

describe("resolveLivePlaybackUrl", () => {
  it("joins relative paths via buildStreamUrl", () => {
    expect(resolveLivePlaybackUrl("https://prairie.example", "/live.m3u8", "tok")).toBe(
      "https://prairie.example/live.m3u8?token=tok",
    );
    expect(
      resolveLivePlaybackUrl("https://prairie.example", "/live.m3u8", "tok", "profile-1"),
    ).toBe("https://prairie.example/live.m3u8?token=tok&profile_id=profile-1");
  });

  it("allows same-origin absolute URLs", () => {
    expect(
      resolveLivePlaybackUrl(
        "https://prairie.example",
        "https://prairie.example/api/v1/livetv/proxy.m3u8",
        "tok",
        "profile-1",
      ),
    ).toBe("https://prairie.example/api/v1/livetv/proxy.m3u8?token=tok&profile_id=profile-1");
  });

  it("rejects cross-origin absolute tuner URLs", () => {
    expect(() => resolveLivePlaybackUrl("https://prairie.example", "   ", "tok")).toThrow(
      "Live TV session returned no stream URL",
    );
    expect(() =>
      resolveLivePlaybackUrl("https://prairie.example", "http://tuner.local:5004/auto/v4.1", "tok"),
    ).toThrow("Live TV requires a server-proxied stream");
  });
});

describe("channelDisplayLabel", () => {
  it("uses name, callsign, then channel number", () => {
    expect(channelDisplayLabel(channel)).toBe("Prairie Local");
    expect(channelDisplayLabel({ ...channel, name: "", callsign: "KTV" })).toBe("KTV");
    expect(channelDisplayLabel({ ...channel, name: "", callsign: "", number: "7" })).toBe(
      "Channel 7",
    );
    expect(
      channelDisplayLabel({
        ...channel,
        name: "",
        callsign: "",
        number: "",
        number_override: "9.1",
      }),
    ).toBe("Channel 9.1");
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
    expect(nextProgramForChannel(programs, "missing", now)).toBeNull();
    expect(
      currentProgramForChannel([{ ...programs[0]!, start: "bad", stop: "bad" }], "ch-1", now),
    ).toBeNull();
  });
});

describe("Live TV API", () => {
  it("lists enabled channels and treats 404 as empty", async () => {
    const ok = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            channels: [channel, { ...channel, id: "off", enabled: false }],
          }),
          { status: 200 },
        ),
    );
    const list = await fetchLiveTvChannels(session, ok);
    expect(list).toHaveLength(1);
    expect(list[0]?.id).toBe("ch-1");

    const missing = vi.fn(async () => new Response("nope", { status: 404 }));
    await expect(fetchLiveTvChannels(session, missing)).resolves.toEqual([]);

    const boom = vi.fn(async () => new Response("nope", { status: 500 }));
    await expect(fetchLiveTvChannels(session, boom)).rejects.toThrow();
  });

  it("loads guide, starts, and releases sessions", async () => {
    const guideFetch = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/livetv/guide?channels=ch-1");
      return new Response(JSON.stringify({}), { status: 200 });
    });
    await expect(fetchLiveTvGuide(session, ["ch-1"], guideFetch)).resolves.toEqual([]);
    await expect(fetchLiveTvGuide(session, [])).resolves.toEqual([]);

    const startFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/channels/ch-1/session");
      expect(init?.method).toBe("POST");
      return new Response(
        JSON.stringify({
          session_id: "live-1",
          hls_url: "/live.m3u8",
          transport: "hls",
        }),
        { status: 200 },
      );
    });
    const started = await startLiveTvSession(session, "ch-1", startFetch);
    expect(started.session_id).toBe("live-1");
    expect(started.transport).toBe("hls");

    const releaseFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/sessions/live-1");
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await releaseLiveTvSession(session, "live-1", releaseFetch);
    expect(releaseFetch).toHaveBeenCalledOnce();
  });

  it("lists and cancels recordings", async () => {
    const listFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/recordings");
      expect(init?.method).toBeUndefined();
      return new Response(
        JSON.stringify({
          recordings: [
            {
              id: "rec-1",
              channel_id: "ch-1",
              status: "scheduled",
              start: "2026-07-25T19:00:00.000Z",
              stop: "2026-07-25T20:00:00.000Z",
              title: "Now Show",
            },
          ],
        }),
        { status: 200 },
      );
    });
    const recordings = await fetchLiveTvRecordings(session, listFetch);
    expect(recordings).toHaveLength(1);
    expect(recordings[0]?.id).toBe("rec-1");

    const missing = vi.fn(async () => new Response("nope", { status: 404 }));
    await expect(fetchLiveTvRecordings(session, missing)).resolves.toEqual([]);

    const cancelFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/recordings/rec-1");
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await cancelLiveTvRecording(session, "rec-1", cancelFetch);
    expect(cancelFetch).toHaveBeenCalledOnce();

    await expect(cancelLiveTvRecording(session, "  ")).rejects.toThrow(/Missing recording id/i);
  });

  it("schedules a recording by program id", async () => {
    const recordFetch = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/livetv/recordings");
      expect(init?.method).toBe("POST");
      expect(JSON.parse(String(init?.body))).toEqual({ program_id: "p1" });
      return new Response(
        JSON.stringify({
          id: "rec-1",
          program_id: "p1",
          channel_id: "ch-1",
          status: "scheduled",
          start: "2026-07-25T19:00:00.000Z",
          stop: "2026-07-25T20:00:00.000Z",
          title: "Now Show",
        }),
        { status: 201 },
      );
    });

    const recording = await scheduleLiveTvRecording(session, { program_id: "p1" }, recordFetch);
    expect(recording.id).toBe("rec-1");
    expect(recording.status).toBe("scheduled");

    await expect(scheduleLiveTvRecording(session, { program_id: "  " })).rejects.toThrow(
      /Missing program id/i,
    );
  });
});
