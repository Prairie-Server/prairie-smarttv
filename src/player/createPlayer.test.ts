import { describe, expect, it } from "vitest";
import { selectPlayerBackend } from "./createPlayer";

describe("selectPlayerBackend", () => {
  it("auto uses AVPlay on Tizen when available", () => {
    expect(
      selectPlayerBackend({
        preference: "auto",
        platform: "tizen",
        avplayAvailable: true,
        starfishAvailable: false,
      }),
    ).toBe("avplay");
  });

  it("auto uses Starfish-style on webOS", () => {
    expect(
      selectPlayerBackend({
        preference: "auto",
        platform: "webos",
        avplayAvailable: false,
        starfishAvailable: true,
      }),
    ).toBe("starfish");
  });

  it("auto uses HTML5 in browser", () => {
    expect(
      selectPlayerBackend({
        preference: "auto",
        platform: "browser",
        avplayAvailable: false,
        starfishAvailable: false,
      }),
    ).toBe("html5");
  });

  it("html5 preference always wins", () => {
    expect(
      selectPlayerBackend({
        preference: "html5",
        platform: "tizen",
        avplayAvailable: true,
      }),
    ).toBe("html5");
  });

  it("native preference falls back to HTML5 when unavailable", () => {
    expect(
      selectPlayerBackend({
        preference: "native",
        platform: "browser",
        avplayAvailable: false,
        starfishAvailable: false,
      }),
    ).toBe("html5");
  });

  it("native preference selects AVPlay on Tizen", () => {
    expect(
      selectPlayerBackend({
        preference: "native",
        platform: "tizen",
        avplayAvailable: true,
      }),
    ).toBe("avplay");
  });
});
