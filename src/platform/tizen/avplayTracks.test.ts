import { describe, expect, it } from "vitest";
import { pickExternalTextTrackIndex } from "./avplayTracks";

describe("pickExternalTextTrackIndex", () => {
  it("returns the last TEXT track index", () => {
    expect(
      pickExternalTextTrackIndex([
        { type: "AUDIO", index: 0 },
        { type: "TEXT", index: 2 },
        { type: "text", index: 5 },
      ]),
    ).toBe(5);
    expect(pickExternalTextTrackIndex([{ type: "AUDIO", index: 0 }])).toBeNull();
  });
});
