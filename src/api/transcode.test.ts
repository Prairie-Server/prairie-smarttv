import { describe, expect, it, vi } from "vitest";
import { buildTranscodeStartRequest, needsHlsBootstrap, preparePlayableSession } from "./transcode";
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

describe("needsHlsBootstrap", () => {
  it("is true for remux and transcode only", () => {
    expect(needsHlsBootstrap("direct")).toBe(false);
    expect(needsHlsBootstrap("remux")).toBe(true);
    expect(needsHlsBootstrap("TRANSCODE")).toBe(true);
    expect(needsHlsBootstrap(null)).toBe(false);
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

  it("uses h264/aac for transcode", () => {
    const body = buildTranscodeStartRequest({
      sessionId: "s1",
      seekSeconds: 0,
      playMethod: "transcode",
    });
    expect(body.target_codec_video).toBe("h264");
    expect(body.target_codec_audio).toBe("aac");
    expect(body.target_resolution).toBe("1080p");
    expect(body.target_bitrate_kbps).toBe(6000);
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
        }),
        { status: 200 },
      );
    });

    const prepared = await preparePlayableSession(session, started("remux"), 12, fetchImpl);
    expect(prepared.session.stream_url).toContain("master.m3u8");
    expect(prepared.streamUrl).toContain("master.m3u8");
    expect(prepared.streamUrl).toContain("token=tok");
    expect(prepared.playerStartSeconds).toBe(12);
    expect(prepared.session.play_method).toBe("remux");
  });
});
