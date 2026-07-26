import { describe, expect, it } from "vitest";
import { filterClientRenderableSubtitles, isClientRenderableSubtitleUrl } from "./subtitleFormats";

describe("subtitleFormats", () => {
  it("accepts only WebVTT URLs for native <track> backends", () => {
    expect(isClientRenderableSubtitleUrl("https://x/a.vtt?token=1")).toBe(true);
    expect(isClientRenderableSubtitleUrl("https://x/a.srt")).toBe(false);
    expect(isClientRenderableSubtitleUrl("https://x/a.smi")).toBe(false);
  });

  it("rejects bitmap/ASS and non-WebVTT text tracks", () => {
    expect(isClientRenderableSubtitleUrl("https://x/a.sup")).toBe(false);
    expect(
      filterClientRenderableSubtitles([
        { url: "https://x/a.vtt" },
        { url: "https://x/a.srt", codec: "srt" },
        { url: "https://x/a.sup", codec: "pgs" },
        { url: "https://x/a.ass", codec: "ass" },
      ]),
    ).toEqual([{ url: "https://x/a.vtt" }]);
  });
});
