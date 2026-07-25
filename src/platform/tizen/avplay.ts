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
  getCurrentTimeMs(): number;
  getDurationMs(): number;
}

export interface AvPlayPlayerOptions {
  url: string;
  container: HTMLElement;
  autoplay?: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
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
  });

  let destroyed = false;

  const prepareAndPlay = () => {
    if (destroyed) return;
    try {
      if (typeof avplay.prepareAsync === "function") {
        avplay.prepareAsync(
          () => {
            if (!destroyed && options.autoplay !== false) avplay.play();
          },
          (err) => options.onError?.(String(err)),
        );
      } else {
        avplay.prepare();
        if (options.autoplay !== false) avplay.play();
      }
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  prepareAndPlay();

  return {
    play: () => {
      if (!destroyed) avplay.play();
    },
    pause: () => {
      if (!destroyed) avplay.pause();
    },
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
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
    getCurrentTimeMs: () => {
      try {
        return avplay.getCurrentTime();
      } catch {
        return 0;
      }
    },
    getDurationMs: () => {
      try {
        return avplay.getDuration();
      } catch {
        return 0;
      }
    },
  };
}
