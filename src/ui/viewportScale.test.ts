import { describe, expect, it, afterEach, vi } from "vitest";
import {
  applyViewportScale,
  currentViewportWidth,
  designPx,
  detectPanelClass,
  PANEL_CHROME_SCALE,
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

  it("is 1× at 1920 design width on FHD", () => {
    expect(viewportScaleFactor(1920, "fhd")).toBe(1);
    expect(rootFontSizePx(1)).toBe(16);
    expect(designPx(155, 1)).toBe(155);
  });

  it("doubles at 4K and quadruples at 8K CSS widths", () => {
    expect(viewportScaleFactor(3840)).toBe(2);
    expect(viewportScaleFactor(7680)).toBe(4);
    expect(designPx(155, 2)).toBe(310);
    expect(designPx(155, 4)).toBe(620);
    expect(designPx(0.2, 1)).toBe(1);
  });

  it("applies panel chrome when CSS viewport stays at 1920", () => {
    expect(viewportScaleFactor(1920, "uhd")).toBe(PANEL_CHROME_SCALE.uhd);
    expect(viewportScaleFactor(1920, "uhd8k")).toBe(PANEL_CHROME_SCALE.uhd8k);
  });

  it("detects panel class from productinfo and screen size", () => {
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 1920,
        productInfo: {
          is8KPanelSupported: () => true,
          isUdPanelSupported: () => true,
        },
      }),
    ).toBe("uhd8k");
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 1920,
        productInfo: {
          is8KPanelSupported: () => false,
          isUdPanelSupported: () => true,
        },
      }),
    ).toBe("uhd");
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 7680,
        productInfo: null,
      }),
    ).toBe("uhd8k");
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 3840,
        productInfo: null,
      }),
    ).toBe("uhd");
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 1920,
        productInfo: null,
      }),
    ).toBe("fhd");
  });

  it("tolerates productinfo probe failures", () => {
    expect(
      detectPanelClass({
        cssWidth: 1920,
        screenWidth: 1920,
        productInfo: {
          is8KPanelSupported: () => {
            throw new Error("denied");
          },
          isUdPanelSupported: () => {
            throw new Error("denied");
          },
        },
      }),
    ).toBe("fhd");
  });

  it("reads productinfo from window.webapis when present", () => {
    const previous = window.webapis;
    window.webapis = {
      productinfo: {
        is8KPanelSupported: () => false,
        isUdPanelSupported: () => true,
      },
    };
    expect(detectPanelClass({ cssWidth: 1920, screenWidth: 1920 })).toBe("uhd");
    window.webapis = previous;
  });

  it("falls back when productinfo is absent on webapis", () => {
    const previous = window.webapis;
    window.webapis = {};
    expect(detectPanelClass({ cssWidth: 1920, screenWidth: 1920 })).toBe("fhd");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    delete (window as any).webapis;
    expect(detectPanelClass({ cssWidth: 1920, screenWidth: 3840 })).toBe("uhd");
    window.webapis = previous;
  });

  it("uses live window metrics when detectPanelClass args are omitted", () => {
    const previousInner = window.innerWidth;
    const previousScreen = Object.getOwnPropertyDescriptor(window.screen, "width");
    Object.defineProperty(window, "innerWidth", { configurable: true, value: 1920 });
    Object.defineProperty(window.screen, "width", { configurable: true, value: 1920 });
    expect(detectPanelClass({ productInfo: null })).toBe("fhd");
    Object.defineProperty(window, "innerWidth", { configurable: true, value: previousInner });
    if (previousScreen) Object.defineProperty(window.screen, "width", previousScreen);
  });

  it("applies panel chrome via live detect when panelClass is omitted", () => {
    const previous = window.webapis;
    window.webapis = {
      productinfo: {
        is8KPanelSupported: () => true,
      },
    };
    expect(viewportScaleFactor(1920)).toBe(PANEL_CHROME_SCALE.uhd8k);
    window.webapis = {
      productinfo: {
        isUdPanelSupported: () => true,
      },
    };
    expect(viewportScaleFactor(1920)).toBe(PANEL_CHROME_SCALE.uhd);
    window.webapis = previous;
  });

  it("clamps extreme widths", () => {
    expect(viewportScaleFactor(100)).toBe(0.75);
    expect(viewportScaleFactor(20_000)).toBe(4);
    expect(viewportScaleFactor(0)).toBe(1);
    expect(viewportScaleFactor(Number.NaN)).toBe(1);
  });

  it("reads current viewport width", () => {
    const original = window.innerWidth;
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: 3840,
    });
    expect(currentViewportWidth()).toBe(3840);
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: 0,
    });
    expect(currentViewportWidth()).toBe(1920);
    Object.defineProperty(window, "innerWidth", {
      configurable: true,
      value: original,
    });
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
