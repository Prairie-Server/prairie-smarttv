import { describe, expect, it, vi } from "vitest";
import {
  reportPlaybackProgress,
  resolveMediaUrl,
  stopPlaybackSession,
  switchPlaybackAudio,
} from "./playbackSession";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  username: "ada",
  profileId: "profile-1",
};

describe("playbackSession", () => {
  it("reports progress", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/s1/progress");
      expect(init?.method).toBe("POST");
      expect(JSON.parse(String(init?.body))).toEqual({ position: 12.5, is_paused: true });
      return new Response(null, { status: 204 });
    });
    await reportPlaybackProgress(session, "s1", 12.5, true, fetchImpl);
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it("stops a session", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/s1");
      expect(init?.method).toBe("DELETE");
      return new Response(null, { status: 204 });
    });
    await stopPlaybackSession(session, "s1", fetchImpl);
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it("switches audio", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/s1/audio");
      expect(init?.method).toBe("PATCH");
      expect(JSON.parse(String(init?.body))).toEqual({
        audio_track_index: 2,
        position: 40,
      });
      return new Response(
        JSON.stringify({
          audio_track_index: 2,
          play_method: "transcode",
          stream_url: "/api/v1/stream/next",
          switch_mode: "reload",
        }),
        { status: 200 },
      );
    });
    const resp = await switchPlaybackAudio(session, "s1", 2, 40, fetchImpl);
    expect(resp.stream_url).toBe("/api/v1/stream/next");
    expect(resp.switch_mode).toBe("reload");
  });

  it("resolves media urls with tokens", () => {
    expect(resolveMediaUrl("https://prairie.example", "/api/v1/stream/x", "tok")).toBe(
      "https://prairie.example/api/v1/stream/x?token=tok",
    );
  });
});
