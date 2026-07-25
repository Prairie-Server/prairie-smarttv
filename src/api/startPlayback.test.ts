import { describe, expect, it, vi } from "vitest";
import { resolvePlaybackStreamUrl, startPlayback } from "./startPlayback";

describe("startPlayback", () => {
  it("posts the playback start body", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/playback/start");
      expect(init?.method).toBe("POST");
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

    const session = await startPlayback(
      "https://prairie.example",
      "tok",
      { fileId: 42, profileId: "p1" },
      fetchImpl,
    );
    expect(session.stream_url).toBe("/api/v1/stream/abc");
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
