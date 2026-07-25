export interface AvPlayListener {
  onbufferingstart?: () => void;
  onbufferingprogress?: (percent: number) => void;
  onbufferingcomplete?: () => void;
  oncurrentplaytime?: (currentTime: number) => void;
  onstreamcompleted?: () => void;
  onevent?: (eventType: string, eventData: string) => void;
  onerror?: (eventType: string) => void;
}

export interface AvPlayApi {
  open(url: string): void;
  close(): void;
  prepare(): void;
  prepareAsync(success?: () => void, error?: (err: unknown) => void): void;
  setDisplayRect(x: number, y: number, width: number, height: number): void;
  setListener(listener: AvPlayListener): void;
  play(): void;
  pause(): void;
  stop(): void;
  getState(): string;
  getDuration(): number;
  getCurrentTime(): number;
  seekTo(milliseconds: number, success?: () => void, error?: (err: unknown) => void): void;
}

export interface AvPlayPlayerHandle {
  play(): void;
  pause(): void;
  destroy(): void;
  seekTo(seconds: number): void;
  getCurrentTime(): number;
  getDuration(): number;
  setTextTrack(url: string | null, label?: string): void;
}

export interface AvPlayPlayerOptions {
  url: string;
  container: HTMLElement;
  autoplay?: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
  onTimeUpdate?: (currentSeconds: number, durationSeconds: number) => void;
}

function getAvPlay(): AvPlayApi | null {
  return window.webapis?.avplay ?? null;
}

export function isAvPlayAvailable(): boolean {
  return getAvPlay() != null;
}

/**
 * Thin wrapper around Samsung AVPlay. Destroy (stop+close) must be called on
 * Back so the native surface does not linger over the React UI.
 */
export function createAvPlayPlayer(options: AvPlayPlayerOptions): AvPlayPlayerHandle {
  const avplay = getAvPlay();
  if (!avplay) {
    throw new Error("AVPlay is not available on this platform");
  }

  const rect = options.container.getBoundingClientRect();
  const width = Math.max(1, Math.floor(rect.width || window.innerWidth));
  const height = Math.max(1, Math.floor(rect.height || window.innerHeight));

  avplay.open(options.url);
  avplay.setDisplayRect(0, 0, width, height);
  avplay.setListener({
    onerror: (eventType) => options.onError?.(String(eventType)),
    onstreamcompleted: () => options.onEnded?.(),
    oncurrentplaytime: (currentTimeMs) => {
      let durationMs = 0;
      try {
        durationMs = avplay.getDuration();
      } catch {
        durationMs = 0;
      }
      options.onTimeUpdate?.(currentTimeMs / 1000, durationMs / 1000);
    },
  });

  let destroyed = false;
  let ready = false;
  let playWhenReady = options.autoplay !== false;

  const safePlay = () => {
    if (destroyed) return;
    try {
      avplay.play();
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  const safePause = () => {
    if (destroyed) return;
    try {
      avplay.pause();
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  const prepareAndPlay = () => {
    if (destroyed) return;
    try {
      if (typeof avplay.prepareAsync === "function") {
        avplay.prepareAsync(
          () => {
            if (destroyed) return;
            ready = true;
            if (playWhenReady) safePlay();
          },
          (err) => options.onError?.(String(err)),
        );
      } else {
        avplay.prepare();
        ready = true;
        if (playWhenReady) safePlay();
      }
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  prepareAndPlay();

  return {
    play: () => {
      if (destroyed) return;
      if (!ready) {
        playWhenReady = true;
        return;
      }
      safePlay();
    },
    pause: () => {
      if (destroyed) return;
      playWhenReady = false;
      if (!ready) return;
      safePause();
    },
    seekTo: (seconds: number) => {
      if (destroyed || !ready) return;
      try {
        avplay.seekTo(Math.max(0, Math.floor(seconds * 1000)));
      } catch (err) {
        options.onError?.(err instanceof Error ? err.message : String(err));
      }
    },
    getCurrentTime: () => {
      try {
        return avplay.getCurrentTime() / 1000;
      } catch {
        return 0;
      }
    },
    getDuration: () => {
      try {
        return avplay.getDuration() / 1000;
      } catch {
        return 0;
      }
    },
    // AVPlay text-track APIs vary by firmware; Off/On is handled via HTML overlay
    // when the stream does not expose embedded text. Keep as intentional no-op.
    setTextTrack: () => undefined,
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      ready = false;
      playWhenReady = false;
      try {
        avplay.stop();
      } catch {
        /* ignore */
      }
      try {
        avplay.close();
      } catch {
        /* ignore */
      }
    },
  };
}
