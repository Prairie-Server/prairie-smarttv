import { describe, expect, it, afterEach, vi } from "vitest";
import {
  applyViewportScale,
  currentViewportWidth,
  designPx,
  rootFontSizePx,
  viewportScaleFactor,
  watchViewportScale,
} from "./viewportScale";

describe("viewportScale", () => {
  afterEach(() => {
    document.documentElement.style.fontSize = "";
    document.documentElement.style.removeProperty("--ui-scale");
    vi.unstubAllGlobals();
  });

  it("is 1× at 1920 design width", () => {
    expect(viewportScaleFactor(1920)).toBe(1);
    expect(rootFontSizePx(1)).toBe(16);
    expect(designPx(155, 1)).toBe(155);
  });

  it("doubles at 4K and quadruples at 8K", () => {
    expect(viewportScaleFactor(3840)).toBe(2);
    expect(viewportScaleFactor(7680)).toBe(4);
    expect(designPx(155, 2)).toBe(310);
    expect(designPx(155, 4)).toBe(620);
    expect(designPx(0.2, 1)).toBe(1);
  });

  it("clamps extreme widths", () => {
    expect(viewportScaleFactor(100)).toBe(0.75);
    expect(viewportScaleFactor(20_000)).toBe(4);
    expect(viewportScaleFactor(0)).toBe(1);
    expect(viewportScaleFactor(Number.NaN)).toBe(1);
  });

  it("reads current viewport width", () => {
    const original = window.innerWidth;
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 3840 });
    expect(currentViewportWidth()).toBe(3840);
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 0 });
    expect(currentViewportWidth()).toBe(1920);
    Object.defineProperty(window, "innerWidth", { configurable: true, value: original });
  });

  it("applies root font-size and --ui-scale", () => {
    const scale = applyViewportScale(3840);
    expect(scale).toBe(2);
    expect(document.documentElement.style.fontSize).toBe("32px");
    expect(document.documentElement.style.getPropertyValue("--ui-scale")).toBe("2");
    applyViewportScale();
  });

  it("watches resize", () => {
    const stop = watchViewportScale();
    window.dispatchEvent(new Event("resize"));
    expect(document.documentElement.style.fontSize).toMatch(/px$/);
    stop();
  });
});
