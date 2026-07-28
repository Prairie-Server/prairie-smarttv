import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PrairieSession } from "../storage/session";
import { resetBackKeyCoalesceForTests } from "../platform/backKey";

const session: PrairieSession = {
  serverUrl: "https://tv.example.com",
  accessToken: "token",
  username: "user",
  profileId: "p1",
};

const player = {
  play: vi.fn(async () => undefined),
  pause: vi.fn(),
  seekTo: vi.fn(async () => undefined),
  getCurrentTime: vi.fn(() => 12),
  getDuration: vi.fn(() => 120),
  setTextTrack: vi.fn(async () => undefined),
  destroy: vi.fn(),
  backend: "html5" as const,
};

vi.mock("../player/PlayerHost", () => ({
  PlayerHost: (props: {
    onReady?: (p: typeof player) => void;
    onTimeUpdate?: (t: number, d: number) => void;
  }) => {
    // Grant a ready player on mount so chrome can auto-hide.
    queueMicrotask(() => props.onReady?.(player));
    return <div className="player-host-mock" />;
  },
}));

vi.mock("../api/startPlayback", () => ({
  startPlayback: vi.fn(async () => ({
    session_id: "sid-1",
    media_file_id: 9,
    play_method: "direct",
    stream_url: "/stream.m3u8",
    position: 0,
    duration_seconds: 120,
    subtitle_urls: [{ index: 0, language: "eng", codec: "webvtt", url: "/subs/eng.vtt" }],
    audio_track_index: 0,
    playback_info: { stream_type: "hls" },
  })),
}));

vi.mock("../api/transcode", () => ({
  preparePlayableSession: vi.fn(async (_session: unknown, started: { session_id: string }) => ({
    session: started,
    streamUrl: "https://tv.example.com/stream.m3u8",
    streamOriginSeconds: 0,
    playerStartSeconds: 0,
  })),
}));

vi.mock("../api/playbackSession", () => ({
  reportPlaybackProgress: vi.fn(async () => undefined),
  stopPlaybackSession: vi.fn(async () => undefined),
  switchPlaybackAudio: vi.fn(async () => ({})),
}));

vi.mock("../api/watch", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../api/watch")>();
  return {
    ...actual,
    fetchWatchDetail: vi.fn(async () => ({
      content_id: "m1",
      type: "movie",
      title: "Movie m1",
      versions: [{ file_id: 9, resolution: "1080p", audio_tracks: [] }],
    })),
  };
});

vi.mock("../platform/tizen/deviceCapabilities", () => ({
  resolveAdvertisedCapabilities: () => ({
    codecs_video: ["h264"],
    codecs_audio: ["aac"],
    containers: ["hls"],
    max_resolution: "1080p",
    hdr: [],
  }),
  probeTvPlaybackCapabilities: () => ({
    codecs_video: ["h264"],
    codecs_audio: ["aac"],
    containers: ["hls"],
    max_resolution: "1080p",
    hdr: [],
  }),
}));

vi.mock("../platform/detect", () => ({
  detectPlatform: () => "web",
}));

vi.mock("../player/createPlayer", () => ({
  selectPlayerBackend: () => "html5",
}));

let container: HTMLDivElement;
let root: Root | null = null;
let exited = false;

async function renderPlayer() {
  const { PlayerScreen } = await import("./PlayerScreen");
  const { ServerUrlContext } = await import("../serverUrlContext");
  await act(async () => {
    root = createRoot(container);
    root.render(
      <ServerUrlContext.Provider value={session.serverUrl}>
        <PlayerScreen
          session={session}
          launch={{ fileId: 9, contentId: "m1", title: "Movie m1" }}
          onExit={() => {
            exited = true;
          }}
        />
      </ServerUrlContext.Provider>,
    );
  });
}

async function settle(ms = 0) {
  await act(async () => {
    await new Promise((resolve) => setTimeout(resolve, ms));
  });
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  exited = false;
  resetBackKeyCoalesceForTests();
  document.documentElement.classList.remove("player-active");
  document.body.classList.remove("player-active");
  vi.useFakeTimers({ shouldAdvanceTime: true });
});

afterEach(async () => {
  if (root) {
    await act(async () => {
      root?.unmount();
    });
    root = null;
  }
  container.remove();
  vi.useRealTimers();
  resetBackKeyCoalesceForTests();
  document.documentElement.classList.remove("player-active");
  document.body.classList.remove("player-active");
});

describe("PlayerScreen chrome and exit", () => {
  it("auto-hides player chrome after launch", async () => {
    await renderPlayer();
    await settle(20);
    expect(container.querySelector(".player-chrome")).not.toBeNull();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(4100);
    });
    expect(container.querySelector(".player-chrome")).toBeNull();
    expect(container.querySelector(".player-tap-catcher")).not.toBeNull();
  });

  it("does not steal Enter from focused chrome buttons", async () => {
    await renderPlayer();
    await settle(20);
    const rewind = [...container.querySelectorAll("button")].find((b) =>
      (b.textContent ?? "").includes("−15s"),
    );
    expect(rewind).toBeTruthy();
    rewind?.focus();

    const playingBefore = container.textContent?.includes("Pause");
    const event = new KeyboardEvent("keydown", {
      key: "Enter",
      bubbles: true,
      cancelable: true,
    });
    Object.defineProperty(event, "target", { value: rewind });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(false);
    // Global handler must not flip Play/Pause when a button is focused.
    expect(container.textContent?.includes("Pause")).toBe(playingBefore);
  });

  /** Label of the middle transport button ("Play" / "Pause"). */
  function transportLabel(): string {
    const buttons = [...container.querySelectorAll(".player-controls button")];
    return buttons[1]?.textContent?.trim() ?? "";
  }

  it("reveals chrome on OK after auto-hide without toggling playback", async () => {
    await renderPlayer();
    await settle(20);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(4100);
    });
    expect(container.querySelector(".player-chrome")).toBeNull();

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", cancelable: true }));
    });
    expect(container.querySelector(".player-chrome")).not.toBeNull();
    // Still playing: OK is the select key, not a transport key.
    expect(transportLabel()).toBe("Pause");
  });

  it("toggles playback on the remote play/pause key", async () => {
    await renderPlayer();
    await settle(20);
    expect(transportLabel()).toBe("Pause");

    await act(async () => {
      // Tizen delivers this as a bare keyCode with no usable `key`.
      window.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Unidentified", keyCode: 10252, cancelable: true }),
      );
    });
    expect(transportLabel()).toBe("Play");
  });

  it("closes the subtitle menu on Back instead of exiting", async () => {
    await renderPlayer();
    await settle(20);
    const subs = [...container.querySelectorAll("button")].find((b) =>
      (b.textContent ?? "").includes("Subs"),
    );
    expect(subs).toBeTruthy();
    await act(async () => {
      subs?.click();
    });
    expect(container.querySelector(".player-menu")).not.toBeNull();

    await act(async () => {
      document.dispatchEvent(
        Object.assign(new Event("tizenhwkey", { cancelable: true }), { keyName: "back" }),
      );
    });
    expect(container.querySelector(".player-menu")).toBeNull();
    expect(exited).toBe(false);
  });

  it("reveals chrome on D-pad after auto-hide", async () => {
    await renderPlayer();
    await settle(20);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(4100);
    });
    expect(container.querySelector(".player-chrome")).toBeNull();

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true }));
    });
    expect(container.querySelector(".player-chrome")).not.toBeNull();
  });

  it("exits on tizenhwkey back and clears player-active", async () => {
    await renderPlayer();
    await settle(20);
    expect(document.documentElement.classList.contains("player-active")).toBe(true);

    await act(async () => {
      document.dispatchEvent(
        Object.assign(new Event("tizenhwkey", { cancelable: true }), { keyName: "Back" }),
      );
    });

    expect(exited).toBe(true);
    expect(document.documentElement.classList.contains("player-active")).toBe(false);
    expect(document.body.classList.contains("player-active")).toBe(false);
    expect(player.destroy).toHaveBeenCalled();
  });
});
