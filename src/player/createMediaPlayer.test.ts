import { describe, expect, it, vi } from "vitest";

vi.mock("../platform/tizen/avplay", () => ({
  createAvPlayPlayer: () => ({
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
    seekTo: vi.fn(),
    getCurrentTime: vi.fn(() => 0),
    getDuration: vi.fn(() => 0),
    setTextTrack: vi.fn(),
  }),
}));

vi.mock("../platform/webos/starfish", () => ({
  createStarfishPlayer: () => ({
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
    seekTo: vi.fn(),
    getCurrentTime: vi.fn(() => 0),
    getDuration: vi.fn(() => 0),
    setTextTrack: vi.fn(),
  }),
}));

vi.mock("./html5Player", () => ({
  createHtml5Player: () => ({
    backend: "html5",
    play: vi.fn(),
    pause: vi.fn(),
    destroy: vi.fn(),
    seekTo: vi.fn(),
    getCurrentTime: vi.fn(() => 0),
    getDuration: vi.fn(() => 0),
    setTextTrack: vi.fn(),
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
    void player.seekTo(12);
    expect(player.getCurrentTime()).toBe(0);
    expect(player.getDuration()).toBe(0);
    void player.setTextTrack(null);
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
    void player.seekTo(3);
    expect(player.getCurrentTime()).toBe(0);
    expect(player.getDuration()).toBe(0);
    void player.setTextTrack("https://example/sub.vtt", "English");
    player.destroy();
  });

  it("falls back to HTML5", () => {
    const player = createMediaPlayer({
      backend: "html5",
      url: "https://example/stream",
      container,
    });
    expect(player.backend).toBe("html5");
    void player.seekTo(1);
    void player.setTextTrack(null);
  });
});
