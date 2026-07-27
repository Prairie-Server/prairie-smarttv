import { describe, expect, it } from "vitest";
import { humanizePlaybackError } from "./humanizePlaybackError";

describe("humanizePlaybackError", () => {
  it("maps AVPlay connection failures", () => {
    expect(humanizePlaybackError("PLAYER_ERR_CONNECTION_FAILED")).toMatch(/connect/i);
  });

  it("maps transcode startup timeout", () => {
    expect(humanizePlaybackError("Transcode timed out")).toBe("Transcode timed out");
  });

  it("maps network errors", () => {
    expect(humanizePlaybackError("PLAYER_ERR_NETWORK_UNAVAILABLE")).toMatch(/Network/i);
  });

  it("maps missing stream errors", () => {
    expect(humanizePlaybackError("PLAYER_ERR_NO_SUCH_FILE")).toMatch(/not found/i);
  });

  it("maps invalid URI errors", () => {
    expect(humanizePlaybackError("PLAYER_ERR_INVALID_URI")).toMatch(/Invalid stream/i);
  });

  it("maps seek errors", () => {
    expect(humanizePlaybackError("PLAYER_ERR_SEEK_FAILED")).toMatch(/seek/i);
  });

  it("maps codec errors toward a Transcode hint", () => {
    expect(humanizePlaybackError("PLAYER_ERR_NONE_SUPPORTED_CODEC")).toMatch(/Transcode/);
  });

  it("maps generic AVPlay errors", () => {
    expect(humanizePlaybackError("PLAYER_ERR_UNKNOWN")).toMatch(/TV player/i);
  });

  it("maps HTML5 media error codes", () => {
    expect(humanizePlaybackError("Media error 4")).toMatch(/decode/i);
  });

  it("passes through already-friendly messages", () => {
    expect(humanizePlaybackError("Could not start HLS playback")).toBe(
      "Could not start HLS playback",
    );
  });

  it("handles empty input", () => {
    expect(humanizePlaybackError("")).toBe("Playback failed");
  });
});
