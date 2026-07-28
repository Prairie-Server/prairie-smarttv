import { afterEach, describe, expect, it, vi } from "vitest";
import {
  avPlayFixedMaxResolution,
  probePanelMaxResolution,
  resolutionTokenFromPixels,
  resolutionTokenFromSize,
} from "./displayResolution";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("resolutionTokenFromSize", () => {
  it("maps common panel sizes", () => {
    expect(resolutionTokenFromSize(3840, 2160)).toBe("2160p");
    expect(resolutionTokenFromSize(7680, 4320)).toBe("2160p");
    expect(resolutionTokenFromSize(2560, 1440)).toBe("1440p");
    expect(resolutionTokenFromSize(1920, 1080)).toBe("1080p");
    expect(resolutionTokenFromSize(1280, 720)).toBe("720p");
  });
});

describe("resolutionTokenFromPixels", () => {
  it("parses WxH and token-like strings", () => {
    expect(resolutionTokenFromPixels("3840x2160")).toBe("2160p");
    expect(resolutionTokenFromPixels("7680x4320")).toBe("2160p");
    expect(resolutionTokenFromPixels("4K")).toBe("2160p");
    expect(resolutionTokenFromPixels("")).toBe("");
  });
});

describe("probePanelMaxResolution", () => {
  it("prefers ProductInfo over a 1080p logical webview", () => {
    expect(
      probePanelMaxResolution({
        productInfo: {
          isUdPanelSupported: () => true,
          is8KPanelSupported: () => false,
        },
        screenWidth: 1920,
        screenHeight: 1080,
        windowWidth: 1920,
        windowHeight: 1080,
      }),
    ).toBe("2160p");
  });

  it("uses getRealResolution when present", () => {
    expect(
      probePanelMaxResolution({
        productInfo: {
          getRealResolution: () => "3840x2160",
          isUdPanelSupported: () => false,
        },
        screenWidth: 1920,
        screenHeight: 1080,
        windowWidth: 1920,
        windowHeight: 1080,
      }),
    ).toBe("2160p");
  });

  it("falls back to screen/window off-Tizen", () => {
    expect(
      probePanelMaxResolution({
        productInfo: null,
        screenWidth: 1920,
        screenHeight: 1080,
        windowWidth: 1920,
        windowHeight: 1080,
      }),
    ).toBe("1080p");
  });
});

describe("avPlayFixedMaxResolution", () => {
  it("matches the capability token", () => {
    expect(avPlayFixedMaxResolution("2160p")).toBe("3840x2160");
    expect(avPlayFixedMaxResolution("1080p")).toBe("1920x1080");
    expect(avPlayFixedMaxResolution("")).toBe("1920x1080");
  });
});
