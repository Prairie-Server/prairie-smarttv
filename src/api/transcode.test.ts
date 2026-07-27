import { describe, expect, it, vi } from "vitest";
import { ApiError } from "./client";
import {
  buildTranscodeStartRequest,
  needsHlsBootstrap,
  preparePlayableSession,
  startTranscode,
} from "./transcode";
import type { PlaybackSessionResponse } from "../player/types";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  profileId: "p1",
  username: "ada",
};

function started(playMethod: string): PlaybackSessionResponse {
  return {
    session_id: "s1",
    user_id: 1,
    profile_id: "p1",
    media_file_id: 42,
    play_method: playMethod,
    position: 12,
    is_paused: false,
    stream_url: "/api/v1/stream/placeholder",
    audio_track_index: 0,
    duration_seconds: 3600,
  };
}

function manifestResponse(overrides: Record<string, unknown> = {}) {
  return new Response(
    JSON.stringify({
      session_id: "s1",
      status: "ok",
      manifest_url: "/api/v1/playback/transcode/s1/master.m3u8",
      duration_seconds: 3600,
      player_start_seconds: 12,
      stream_origin_seconds: 0,
      timeline_offset_seconds: 0,
      can_seek_anywhere: false,
      ...overrides,
    }),
    { status: 200 },
  );
}

describe("needsHlsBootstrap", () => {
  it("is true for remux and transcode only", () => {
    expect(needsHlsBootstrap("direct")).toBe(false);
    expect(needsHlsBootstrap("remux")).toBe(true);
    expect(needsHlsBootstrap("TRANSCODE")).toBe(true);
    expect(needsHlsBootstrap(null)).toBe(false);
    expect(needsHlsBootstrap(undefined)).toBe(false);
    expect(needsHlsBootstrap("  ")).toBe(false);
  });
});

describe("buildTranscodeStartRequest", () => {
  it("uses codec copy for remux", () => {
    const body = buildTranscodeStartRequest({
      sessionId: "s1",
      seekSeconds: 40,
      playMethod: "remux",
    });
    expect(body).toMatchObject({
      session_id: "s1",
      seek_seconds: 40,
      target_resolution: "",
      target_codec_video: "copy",
      target_codec_audio: "copy",
      target_bitrate_kbps: 0,
    });
  });

  it("uses h264/aac for transcode and clamps negative seek", () => {
    const body = buildTranscodeStartRequest({
      sessionId: "s1",
      seekSeconds: -5,
      playMethod: "transcode",
    });
    expect(body.target_codec_video).toBe("h264");
    expect(body.target_codec_audio).toBe("aac");
    expect(body.target_resolution).toBe("1080p");
    expect(body.target_bitrate_kbps).toBe(6000);
    expect(body.seek_seconds).toBe(0);
  });
});

describe("startTranscode", () => {
  it("posts the transcode start body", async () => {
    let postedUrl = "";
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      postedUrl = String(url);
      return manifestResponse();
    });
    const resp = await startTranscode(
      session,
      buildTranscodeStartRequest({
        sessionId: "s1",
        seekSeconds: 0,
        playMethod: "transcode",
      }),
      fetchImpl,
    );
    expect(resp.manifest_url).toContain("master.m3u8");
    expect(postedUrl).toContain("/playback/transcode/start");
  });
});

describe("preparePlayableSession", () => {
  it("returns stream_url for direct play without a second request", async () => {
    const fetchImpl = vi.fn();
    const prepared = await preparePlayableSession(session, started("direct"), 12, fetchImpl);
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(prepared.streamUrl).toContain("/api/v1/stream/placeholder");
    expect(prepared.streamUrl).toContain("token=tok");
  });

  it("bootstraps HLS and plays manifest_url for remux", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/transcode/start");
      expect(init?.method).toBe("POST");
      const body = JSON.parse(String(init?.body));
      expect(body.target_codec_video).toBe("copy");
      return manifestResponse();
    });

    const prepared = await preparePlayableSession(session, started("remux"), 12, fetchImpl);
    expect(prepared.session.stream_url).toContain("master.m3u8");
    expect(prepared.streamUrl).toContain("master.m3u8");
    expect(prepared.streamUrl).toContain("token=tok");
    expect(prepared.playerStartSeconds).toBe(12);
    expect(prepared.session.play_method).toBe("remux");
  });

  it("bootstraps full encode for transcode and marks can_seek_anywhere", async () => {
    const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body));
      expect(body.target_codec_video).toBe("h264");
      return manifestResponse({
        can_seek_anywhere: true,
        player_start_seconds: 90,
        duration_seconds: null,
        session_id: "",
      });
    });

    const prepared = await preparePlayableSession(session, started("transcode"), 90, fetchImpl);
    expect(prepared.session.play_method).toBe("transcode");
    expect(prepared.session.session_id).toBe("s1");
    expect(prepared.session.duration_seconds).toBe(3600);
    expect(prepared.playerStartSeconds).toBe(90);
    expect(prepared.session.playback_info?.stream_type).toBe("hls");
    expect(prepared.session.playback_info?.can_seek_anywhere).toBe(true);
  });

  it("falls back to h264 encode when remux copy is rejected with 422", async () => {
    const bodies: unknown[] = [];
    const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      bodies.push(JSON.parse(String(init?.body)));
      if (bodies.length === 1) {
        return new Response(JSON.stringify({ error: { message: "no_alternate" } }), {
          status: 422,
        });
      }
      return manifestResponse({
        can_seek_anywhere: true,
        player_start_seconds: 8,
      });
    });

    const prepared = await preparePlayableSession(session, started("remux"), 8, fetchImpl);
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(bodies[0]).toMatchObject({ target_codec_video: "copy" });
    expect(bodies[1]).toMatchObject({
      target_codec_video: "h264",
      target_resolution: "1080p",
    });
    expect(prepared.session.play_method).toBe("transcode");
    expect(prepared.playerStartSeconds).toBe(8);
  });

  it("rethrows non-422 remux failures", async () => {
    const fetchImpl = vi.fn(async () => new Response("boom", { status: 500 }));
    await expect(
      preparePlayableSession(session, started("remux"), 0, fetchImpl),
    ).rejects.toBeInstanceOf(ApiError);
  });

  it("rethrows transcode failures without attempting copy fallback", async () => {
    const fetchImpl = vi.fn(async () => new Response("nope", { status: 422 }));
    await expect(
      preparePlayableSession(session, started("transcode"), 0, fetchImpl),
    ).rejects.toBeInstanceOf(ApiError);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it("uses seekSeconds when player_start_seconds is omitted", async () => {
    const fetchImpl = vi.fn(async () =>
      manifestResponse({
        player_start_seconds: undefined,
        can_seek_anywhere: undefined,
        duration_seconds: undefined,
      }),
    );
    const base = started("remux");
    delete (base as { duration_seconds?: number }).duration_seconds;
    const prepared = await preparePlayableSession(session, base, 44, fetchImpl);
    expect(prepared.playerStartSeconds).toBe(44);
    expect(prepared.session.position).toBe(12);
  });
});
