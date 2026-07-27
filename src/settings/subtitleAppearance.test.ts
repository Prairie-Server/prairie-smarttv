import { describe, expect, it } from "vitest";
import {
  DEFAULT_SUBTITLE_APPEARANCE,
  hexToRgba,
  normalizeSubtitleAppearance,
  subtitleAppearanceCssVars,
} from "./subtitleAppearance";

describe("subtitleAppearance", () => {
  it("normalizes invalid colors and opacity", () => {
    const normalized = normalizeSubtitleAppearance({
      fontColor: "red",
      backgroundColor: "#gg0000",
      backgroundOpacity: 250,
      textOutline: false,
      // @ts-expect-error intentional bad enum
      fontSize: "huge",
    });
    expect(normalized.fontColor).toBe(DEFAULT_SUBTITLE_APPEARANCE.fontColor);
    expect(normalized.backgroundColor).toBe(DEFAULT_SUBTITLE_APPEARANCE.backgroundColor);
    expect(normalized.backgroundOpacity).toBe(100);
    expect(normalized.fontSize).toBe("large");
    expect(normalized.textOutline).toBe(false);

    const defaults = normalizeSubtitleAppearance(null);
    expect(defaults).toEqual(DEFAULT_SUBTITLE_APPEARANCE);
  });

  it("builds CSS variables for box style", () => {
    const vars = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      backgroundStyle: "box",
      backgroundOpacity: 50,
      backgroundColor: "#000000",
      fontSize: "medium",
      position: "top",
    });
    expect(vars["--prairie-sub-color"]).toBe("#ffffff");
    expect(vars["--prairie-sub-bg"]).toBe("rgba(0, 0, 0, 0.5)");
    expect(vars["--prairie-sub-size"]).toBe("36px");
    expect(vars["--prairie-sub-bottom"]).toBe("82%");
  });

  it("uses transparent background when style is none", () => {
    const vars = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      backgroundStyle: "none",
      textOutline: true,
    });
    expect(vars["--prairie-sub-bg"]).toBe("transparent");
    expect(vars["--prairie-sub-shadow"]).not.toBe("none");
  });

  it("converts hex to rgba", () => {
    expect(hexToRgba("#ff0000", 0.25)).toBe("rgba(255, 0, 0, 0.25)");
    expect(hexToRgba("00ff00", 2)).toBe("rgba(0, 255, 0, 1)");
    expect(hexToRgba("0000ff", -1)).toBe("rgba(0, 0, 255, 0)");
  });

  it("builds outline and shadow text styles", () => {
    const outline = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      backgroundStyle: "outline",
      textOutline: false,
      textOutlineColor: "#112233",
    });
    expect(outline["--prairie-sub-shadow"]).toContain("1px 0 0 #112233");

    // Explicit Outline wins even when the textOutline toggle is on (default).
    const outlineWithToggle = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      backgroundStyle: "outline",
      textOutline: true,
      textOutlineColor: "#112233",
    });
    expect(outlineWithToggle["--prairie-sub-shadow"]).toContain("1px 0 0 #112233");
    expect(outlineWithToggle["--prairie-sub-shadow"]).not.toContain("0 0 2px");

    const shadow = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      backgroundStyle: "shadow",
      textOutline: false,
    });
    expect(shadow["--prairie-sub-shadow"]).not.toBe("none");

    const plain = subtitleAppearanceCssVars({
      ...DEFAULT_SUBTITLE_APPEARANCE,
      textOutline: false,
      // @ts-expect-error intentional bad enum
      position: "middle",
      // @ts-expect-error intentional bad enum
      backgroundStyle: "transparent",
    });
    expect(plain["--prairie-sub-shadow"]).toBe("none");
    expect(plain["--prairie-sub-bottom"]).toBe("6%");
  });

  it("clamps non-finite opacity to the default", () => {
    const normalized = normalizeSubtitleAppearance({
      backgroundOpacity: Number.NaN,
    });
    expect(normalized.backgroundOpacity).toBe(DEFAULT_SUBTITLE_APPEARANCE.backgroundOpacity);
  });
});
