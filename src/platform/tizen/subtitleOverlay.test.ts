import { afterEach, describe, expect, it } from "vitest";
import {
  clearSubtitleOverlay,
  createSubtitleOverlay,
  destroySubtitleOverlay,
  formatAvPlaySubtitleText,
  setSubtitleOverlayText,
} from "./subtitleOverlay";

describe("subtitleOverlay", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("formats string and array cue payloads", () => {
    expect(formatAvPlaySubtitleText("Hello")).toBe("Hello");
    expect(formatAvPlaySubtitleText(["Line 1", "Line 2"])).toBe("Line 1\nLine 2");
    expect(formatAvPlaySubtitleText(["", null, "Keep"])).toBe("Keep");
    expect(formatAvPlaySubtitleText(null)).toBe("");
    expect(formatAvPlaySubtitleText(undefined)).toBe("");
    expect(formatAvPlaySubtitleText(42)).toBe("42");
    expect(formatAvPlaySubtitleText(true)).toBe("true");
    expect(formatAvPlaySubtitleText({ cue: "nope" })).toBe("");
    expect(formatAvPlaySubtitleText(["  hi ", 7, { x: 1 }])).toBe("hi\n7");
  });

  it("creates, updates, and destroys the overlay", () => {
    const host = document.createElement("div");
    document.body.append(host);
    const overlay = createSubtitleOverlay(host);
    expect(host.querySelector(".prairie-avplay-subtitle")).toBe(overlay);

    setSubtitleOverlayText(overlay, ["One", "Two"]);
    expect(overlay.hidden).toBe(false);
    expect(overlay.textContent).toContain("One");

    clearSubtitleOverlay(overlay);
    expect(overlay.hidden).toBe(true);

    setSubtitleOverlayText(null, "ignored");
    clearSubtitleOverlay(null);
    destroySubtitleOverlay(null);

    const bare = document.createElement("div");
    setSubtitleOverlayText(bare, "no cue child");

    destroySubtitleOverlay(overlay);
    expect(host.querySelector(".prairie-avplay-subtitle")).toBeNull();
  });
});
