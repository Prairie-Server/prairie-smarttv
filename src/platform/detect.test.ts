import { afterEach, describe, expect, it, vi } from "vitest";
import { detectPlatform, isTvPlatform } from "./detect";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe("detectPlatform", () => {
  it("detects Tizen when AVPlay is present", () => {
    vi.stubGlobal("window", {
      webapis: { avplay: {} },
      navigator: { userAgent: "Mozilla" },
    });
    vi.stubGlobal("navigator", { userAgent: "Mozilla" });
    expect(detectPlatform()).toBe("tizen");
  });

  it("detects Tizen from Samsung TV user agent signals", () => {
    vi.stubGlobal("window", {
      navigator: { userAgent: "SMART-TV; Tizen; Samsung TV" },
    });
    vi.stubGlobal("navigator", { userAgent: "SMART-TV; Tizen; Samsung TV" });
    expect(detectPlatform()).toBe("tizen");
  });

  it("detects webOS via starfish environment", async () => {
    vi.resetModules();
    vi.doMock("./webos/starfish", () => ({
      isStarfishEnvironment: () => true,
    }));
    const mod = await import("./detect");
    vi.stubGlobal("window", { navigator: { userAgent: "Chrome" } });
    vi.stubGlobal("navigator", { userAgent: "Chrome" });
    expect(mod.detectPlatform()).toBe("webos");
    vi.doUnmock("./webos/starfish");
    vi.resetModules();
  });

  it("falls back to browser", () => {
    vi.stubGlobal("window", { navigator: { userAgent: "Chrome" } });
    vi.stubGlobal("navigator", { userAgent: "Chrome" });
    expect(detectPlatform()).toBe("browser");
  });

  it("falls back to browser when window is unavailable", () => {
    vi.stubGlobal("window", undefined);
    vi.stubGlobal("navigator", { userAgent: "SMART-TV; Tizen; Samsung TV" });
    expect(detectPlatform()).toBe("browser");
  });
});

describe("isTvPlatform", () => {
  it("identifies tizen and webos", () => {
    expect(isTvPlatform("tizen")).toBe(true);
    expect(isTvPlatform("webos")).toBe(true);
    expect(isTvPlatform("browser")).toBe(false);
  });

  it("uses detected platform by default", () => {
    vi.stubGlobal("window", {
      webapis: { avplay: {} },
      navigator: { userAgent: "Mozilla" },
    });
    vi.stubGlobal("navigator", { userAgent: "Mozilla" });
    expect(isTvPlatform()).toBe(true);
  });
});
