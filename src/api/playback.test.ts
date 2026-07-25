import { describe, expect, it } from "vitest";
import { buildPlaybackStartRequest, withPlayMethod } from "../api/playback";
import { resolveForcedPlayMethod } from "../settings/playbackSettings";

describe("buildPlaybackStartRequest", () => {
  it("omits play_method by default so Prairie can prefer remux/auto", () => {
    const body = buildPlaybackStartRequest({
      fileId: 42,
      profileId: "profile-1",
      forcedPlayMethod: resolveForcedPlayMethod({
        playerBackend: "auto",
        forceDirectPlay: false,
        forceTranscode: false,
      }),
    });
    expect(body.file_id).toBe(42);
    expect(body.profile_id).toBe("profile-1");
    expect(body.codecs_video.length).toBeGreaterThan(0);
    expect(body.codecs_audio.length).toBeGreaterThan(0);
    expect(body).not.toHaveProperty("play_method");
  });

  it("sets play_method direct when forced", () => {
    const body = buildPlaybackStartRequest({
      fileId: 7,
      profileId: "p",
      forcedPlayMethod: "direct",
    });
    expect(body.play_method).toBe("direct");
  });

  it("sets play_method transcode when forced", () => {
    const body = buildPlaybackStartRequest({
      fileId: 7,
      profileId: "p",
      forcedPlayMethod: "transcode",
    });
    expect(body.play_method).toBe("transcode");
  });

  it("includes start_position only when positive", () => {
    const without = buildPlaybackStartRequest({
      fileId: 1,
      profileId: "p",
      startPosition: 0,
    });
    expect(without).not.toHaveProperty("start_position");

    const withPos = buildPlaybackStartRequest({
      fileId: 1,
      profileId: "p",
      startPosition: 12.5,
    });
    expect(withPos.start_position).toBe(12.5);
  });

  it("withPlayMethod can strip or set method", () => {
    const base = buildPlaybackStartRequest({
      fileId: 1,
      profileId: "p",
      forcedPlayMethod: "direct",
    });
    expect(withPlayMethod(base, null)).not.toHaveProperty("play_method");
    expect(withPlayMethod(base, "remux").play_method).toBe("remux");
  });
});
