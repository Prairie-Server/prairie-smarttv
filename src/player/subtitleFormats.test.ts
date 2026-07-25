import { describe, expect, it } from "vitest";
import { filterClientRenderableSubtitles, isClientRenderableSubtitleUrl } from "./subtitleFormats";

describe("subtitleFormats", () => {
  it("accepts text-based subtitle URLs", () => {
    expect(isClientRenderableSubtitleUrl("https://x/a.vtt?token=1")).toBe(true);
    expect(isClientRenderableSubtitleUrl("https://x/a.srt")).toBe(true);
    expect(isClientRenderableSubtitleUrl("https://x/a.smi")).toBe(true);
  });

  it("rejects bitmap/ASS tracks", () => {
    expect(isClientRenderableSubtitleUrl("https://x/a.sup")).toBe(false);
    expect(
      filterClientRenderableSubtitles([
        { url: "https://x/a.vtt" },
        { url: "https://x/a.sup", codec: "pgs" },
        { url: "https://x/a.ass", codec: "ass" },
      ]),
    ).toEqual([{ url: "https://x/a.vtt" }]);
  });
});
