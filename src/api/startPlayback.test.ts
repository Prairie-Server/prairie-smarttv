import { describe, expect, it, vi } from "vitest";
import { resolvePlaybackStreamUrl, startPlayback } from "./startPlayback";
import type { PrairieSession } from "../storage/session";

const session: PrairieSession = {
  serverUrl: "https://prairie.example",
  accessToken: "tok",
  profileId: "p1",
  username: "ada",
};

describe("startPlayback", () => {
  it("posts the playback start body with profile headers", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/start");
      expect(init?.method).toBe("POST");
      const headers = new Headers(init?.headers);
      expect(headers.get("Authorization")).toBe("Bearer tok");
      expect(headers.get("X-Profile-Id")).toBe("p1");
      const body = JSON.parse(String(init?.body));
      expect(body.file_id).toBe(42);
      expect(body.profile_id).toBe("p1");
      return new Response(
        JSON.stringify({
          session_id: "s1",
          user_id: 1,
          stream_url: "/api/v1/stream/abc",
          play_method: "direct",
          media_file_id: 42,
          profile_id: "p1",
          position: 0,
          is_paused: false,
          audio_track_index: 0,
        }),
        { status: 200 },
      );
    });

    const playback = await startPlayback(session, { fileId: 42, profileId: "p1" }, fetchImpl);
    expect(playback.stream_url).toBe("/api/v1/stream/abc");
  });
});

describe("resolvePlaybackStreamUrl", () => {
  it("attaches the access token to the stream url", () => {
    expect(
      resolvePlaybackStreamUrl(
        "https://prairie.example",
        {
          session_id: "s1",
          user_id: 1,
          stream_url: "/api/v1/stream/abc",
          play_method: "direct",
          media_file_id: 1,
          profile_id: "p1",
          position: 0,
          is_paused: false,
          audio_track_index: 0,
        },
        "tok",
      ),
    ).toBe("https://prairie.example/api/v1/stream/abc?token=tok");
  });
});
