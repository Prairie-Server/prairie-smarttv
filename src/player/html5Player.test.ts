import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const ERROR_TYPES = { MEDIA_ERROR: "mediaError", NETWORK_ERROR: "networkError" } as const;
const EVENTS = { MANIFEST_PARSED: "hlsManifestParsed", ERROR: "hlsError" } as const;

type Handler = (event: string, data: unknown) => void;

class FakeHls {
  static supported = true;
  static instances: FakeHls[] = [];
  static isSupported() {
    return FakeHls.supported;
  }

  config: unknown;
  loadedSource: string | null = null;
  attachedTo: HTMLMediaElement | null = null;
  destroyed = false;
  recoverMediaErrorCalls = 0;
  startLoadCalls = 0;
  private handlers = new Map<string, Handler[]>();

  constructor(config: unknown) {
    this.config = config;
    FakeHls.instances.push(this);
  }

  on(event: string, handler: Handler) {
    const list = this.handlers.get(event) ?? [];
    list.push(handler);
    this.handlers.set(event, list);
  }

  emit(event: string, data?: unknown) {
    for (const handler of this.handlers.get(event) ?? []) handler(event, data);
  }

  loadSource(url: string) {
    this.loadedSource = url;
  }

  attachMedia(media: HTMLMediaElement) {
    this.attachedTo = media;
  }

  recoverMediaError() {
    this.recoverMediaErrorCalls += 1;
  }

  startLoad() {
    this.startLoadCalls += 1;
  }

  destroy() {
    this.destroyed = true;
  }
}

vi.mock("hls.js", () => ({
  default: FakeHls,
  Events: EVENTS,
  ErrorTypes: ERROR_TYPES,
}));

let container: HTMLDivElement;

function createPlayer(overrides: Record<string, unknown> = {}) {
  return import("./html5Player").then(({ createHtml5Player }) =>
    createHtml5Player({
      url: "https://tv.example/transcode/abc/index.m3u8",
      container,
      backend: "html5",
      mimeType: "application/vnd.apple.mpegurl",
      ...overrides,
    } as Parameters<typeof createHtml5Player>[0]),
  );
}

function video(): HTMLVideoElement {
  const el = container.querySelector("video");
  if (!el) throw new Error("no video element");
  return el;
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  FakeHls.instances = [];
  FakeHls.supported = true;
  // happy-dom resolves play() but jsdom-style errors are irrelevant here.
  HTMLMediaElement.prototype.play = vi.fn(async () => {});
  HTMLMediaElement.prototype.pause = vi.fn();
  HTMLMediaElement.prototype.load = vi.fn();
  HTMLMediaElement.prototype.canPlayType = vi.fn((): CanPlayTypeResult => "");
});

afterEach(() => {
  container.remove();
  vi.restoreAllMocks();
});

describe("createHtml5Player with HLS", () => {
  it("loads a manifest through hls.js instead of assigning src", async () => {
    const player = await createPlayer();
    const instance = FakeHls.instances[0];

    expect(instance).toBeDefined();
    expect(instance?.loadedSource).toBe("https://tv.example/transcode/abc/index.m3u8");
    expect(instance?.attachedTo).toBe(video());
    // Assigning src is what silently failed on Tizen.
    expect(video().getAttribute("src")).toBeNull();
    player.destroy();
  });

  it("starts playback once the manifest is parsed", async () => {
    const player = await createPlayer();
    expect(HTMLMediaElement.prototype.play).not.toHaveBeenCalled();
    FakeHls.instances[0]?.emit(EVENTS.MANIFEST_PARSED);
    expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
    player.destroy();
  });

  it("does not autoplay when asked not to", async () => {
    const player = await createPlayer({ autoplay: false });
    FakeHls.instances[0]?.emit(EVENTS.MANIFEST_PARSED);
    expect(HTMLMediaElement.prototype.play).not.toHaveBeenCalled();
    player.destroy();
  });

  it("passes TV-tuned config", async () => {
    const player = await createPlayer();
    expect(FakeHls.instances[0]?.config).toMatchObject({
      enableWorker: false,
      lowLatencyMode: false,
      maxBufferLength: 30,
    });
    player.destroy();
  });

  it("recovers once per failure class, then reports the error", async () => {
    const onError = vi.fn();
    const player = await createPlayer({ onError });
    const instance = FakeHls.instances[0];

    // Non-fatal errors are hls.js's normal chatter.
    instance?.emit(EVENTS.ERROR, { fatal: false, type: ERROR_TYPES.NETWORK_ERROR });
    expect(onError).not.toHaveBeenCalled();

    instance?.emit(EVENTS.ERROR, { fatal: true, type: ERROR_TYPES.MEDIA_ERROR });
    expect(instance?.recoverMediaErrorCalls).toBe(1);
    expect(onError).not.toHaveBeenCalled();

    instance?.emit(EVENTS.ERROR, { fatal: true, type: ERROR_TYPES.NETWORK_ERROR });
    expect(instance?.startLoadCalls).toBe(1);
    expect(onError).not.toHaveBeenCalled();

    // Second failure of a class it already tried to recover: surface it so the
    // UI shows an error instead of buffering forever.
    instance?.emit(EVENTS.ERROR, {
      fatal: true,
      type: ERROR_TYPES.NETWORK_ERROR,
      details: "manifestLoadTimeOut",
    });
    expect(onError).toHaveBeenCalledWith("Could not load stream (manifestLoadTimeOut)");
    player.destroy();
  });

  it("destroys the hls.js instance so segment fetching and buffers are freed", async () => {
    const player = await createPlayer();
    const instance = FakeHls.instances[0];
    player.destroy();
    expect(instance?.destroyed).toBe(true);
    expect(container.querySelector("video")).toBeNull();
  });

  it("still attaches an external subtitle track while hls.js owns the element", async () => {
    const player = await createPlayer();
    void player.setTextTrack("https://tv.example/subs/en.vtt", "English");
    const track = container.querySelector("track");
    expect(track?.getAttribute("src")).toBe("https://tv.example/subs/en.vtt");
    expect(track?.getAttribute("label")).toBe("English");
    void player.setTextTrack(null);
    expect(container.querySelector("track")).toBeNull();
    player.destroy();
  });
});

describe("createHtml5Player without HLS", () => {
  it("assigns src directly for progressive MP4", async () => {
    const player = await createPlayer({
      url: "https://tv.example/stream/abc.mp4",
      mimeType: "video/mp4",
    });
    expect(FakeHls.instances).toHaveLength(0);
    expect(video().getAttribute("src")).toBe("https://tv.example/stream/abc.mp4");
    expect(HTMLMediaElement.prototype.play).toHaveBeenCalled();
    player.destroy();
  });

  it("uses native playback when the WebView reports HLS support", async () => {
    HTMLMediaElement.prototype.canPlayType = vi.fn((): CanPlayTypeResult => "probably");
    const player = await createPlayer();
    expect(FakeHls.instances).toHaveLength(0);
    expect(video().getAttribute("src")).toBe("https://tv.example/transcode/abc/index.m3u8");
    player.destroy();
  });

  it("reports media element errors", async () => {
    const onError = vi.fn();
    const player = await createPlayer({
      url: "https://tv.example/stream/abc.mp4",
      mimeType: "video/mp4",
      onError,
    });
    video().dispatchEvent(new Event("error"));
    expect(onError).toHaveBeenCalled();
    player.destroy();
  });
});
