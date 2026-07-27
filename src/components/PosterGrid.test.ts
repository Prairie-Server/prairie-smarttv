import { describe, expect, it } from "vitest";
import { columnCountForWidth } from "./PosterGrid";
import { designPx, PANEL_CHROME_SCALE } from "../ui/viewportScale";

describe("columnCountForWidth", () => {
  it("matches CSS auto-fill at design scale", () => {
    // 1280px pane, 150px min + 16px gap → floor((1280+16)/(150+16)) = 7
    expect(columnCountForWidth(1280, 150, 16)).toBe(7);
  });

  it("uses scaled metrics so 8K ui-scale does not invent extra columns", () => {
    const scale = PANEL_CHROME_SCALE.uhd8k;
    const minCol = designPx(150, scale);
    const gap = designPx(16, scale);
    // Unscaled JS used to see ~11 columns on a 1920 CSS viewport; scaled
    // metrics keep the count near the rem-based CSS grid (~7).
    const scaled = columnCountForWidth(1920, minCol, gap);
    const naive = columnCountForWidth(1920, 150, 16);
    expect(scaled).toBeLessThan(naive);
    expect(scaled).toBe(7);
  });
});
