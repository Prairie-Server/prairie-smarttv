import { describe, expect, it, vi } from "vitest";

vi.mock("../platform/tizen/avplay", () => ({
  createAvPlayPlayer: () => ({
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
  }),
}));

vi.mock("../platform/webos/starfish", () => ({
  createStarfishPlayer: () => ({
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
  }),
}));

vi.mock("./html5Player", () => ({
  createHtml5Player: () => ({
    backend: "html5",
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
  }),
}));

import { createMediaPlayer } from "./createMediaPlayer";

describe("createMediaPlayer", () => {
  const container = document.createElement("div");

  it("wraps AVPlay", () => {
    const player = createMediaPlayer({
      backend: "avplay",
      url: "https://example/stream",
      container,
    });
    expect(player.backend).toBe("avplay");
    player.play();
    player.pause();
    player.destroy();
  });

  it("wraps Starfish", () => {
    const player = createMediaPlayer({
      backend: "starfish",
      url: "https://example/stream",
      container,
    });
    expect(player.backend).toBe("starfish");
    player.play();
    player.pause();
    player.destroy();
  });

  it("falls back to HTML5", () => {
    const player = createMediaPlayer({
      backend: "html5",
      url: "https://example/stream",
      container,
    });
    expect(player.backend).toBe("html5");
  });
});
