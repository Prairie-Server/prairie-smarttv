import { downloadSubtitleToLocalPath } from "./downloadSubtitle";
import {
  clearSubtitleOverlay,
  createSubtitleOverlay,
  destroySubtitleOverlay,
  setSubtitleOverlayText,
} from "./subtitleOverlay";
import { pickExternalTextTrackIndex, type AvPlayTrackInfo } from "./avplayTracks";

export type { AvPlayTrackInfo };
export { pickExternalTextTrackIndex };

export interface AvPlayListener {
  onbufferingstart?: () => void;
  onbufferingprogress?: (percent: number) => void;
  onbufferingcomplete?: () => void;
  oncurrentplaytime?: (currentTime: number) => void;
  onstreamcompleted?: () => void;
  onevent?: (eventType: string, eventData: string) => void;
  onerror?: (eventType: string) => void;
  /** Fired whenever AVPlay has a new subtitle cue to display. */
  onsubtitlechange?: (
    duration: number,
    text: string | string[],
    data?: unknown,
    attriCount?: unknown,
    attributes?: unknown,
  ) => void;
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
  setExternalSubtitlePath?(path: string): void;
  setSilentSubtitle?(silent: boolean): void;
  setSelectTrack?(type: string, index: number): void;
  getTotalTrackInfo?(): AvPlayTrackInfo[];
  setSubtitlePosition?(positionMs: number): void;
}

export interface TvInfoApi {
  registerInAppCaptionControl?(enabled: boolean): void;
  showCaption?(show: boolean): void;
}

export interface AvPlayPlayerHandle {
  play(): void;
  pause(): void;
  destroy(): void;
  seekTo(seconds: number): void;
  getCurrentTime(): number;
  getDuration(): number;
  setTextTrack(url: string | null, label?: string): void | Promise<void>;
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

function getTvInfo(): TvInfoApi | null {
  return (window.webapis as { tvinfo?: TvInfoApi } | undefined)?.tvinfo ?? null;
}

export function isAvPlayAvailable(): boolean {
  return getAvPlay() != null;
}

function claimInAppCaptions(): void {
  const tvinfo = getTvInfo();
  try {
    tvinfo?.registerInAppCaptionControl?.(true);
    tvinfo?.showCaption?.(true);
  } catch {
    /* older firmwares */
  }
}

/**
 * Thin wrapper around Samsung AVPlay with full external-subtitle support:
 * download remote VTT/SRT/SMI → setExternalSubtitlePath → onsubtitlechange
 * rendered in an HTML overlay (so Prairie subtitle styling applies).
 *
 * Destroy (stop+close) must be called on Back so the native surface does not
 * linger over the React UI.
 */
export function createAvPlayPlayer(options: AvPlayPlayerOptions): AvPlayPlayerHandle {
  const avplay = getAvPlay();
  if (!avplay) {
    throw new Error("AVPlay is not available on this platform");
  }

  claimInAppCaptions();

  const rect = options.container.getBoundingClientRect();
  const width = Math.max(1, Math.floor(rect.width || window.innerWidth));
  const height = Math.max(1, Math.floor(rect.height || window.innerHeight));

  const overlay = createSubtitleOverlay(options.container);

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
    onsubtitlechange: (_duration, text) => {
      if (destroyed || silent) {
        clearSubtitleOverlay(overlay);
        return;
      }
      setSubtitleOverlayText(overlay, text);
    },
  });

  let destroyed = false;
  let ready = false;
  let playWhenReady = options.autoplay !== false;
  let silent = true;
  let trackGeneration = 0;
  let pendingSubtitle: { url: string; label?: string } | null = null;

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

  const applyExternalSubtitle = (localPath: string) => {
    if (!avplay.setExternalSubtitlePath) {
      throw new Error("AVPlay setExternalSubtitlePath is unavailable on this firmware");
    }
    avplay.setExternalSubtitlePath(localPath);
    try {
      avplay.setSilentSubtitle?.(false);
    } catch {
      /* ignore */
    }
    silent = false;
    try {
      const tracks = avplay.getTotalTrackInfo?.() ?? [];
      const index = pickExternalTextTrackIndex(tracks);
      if (index != null) {
        avplay.setSelectTrack?.("TEXT", index);
      }
    } catch {
      /* some streams expose the external track without enumeration */
    }
  };

  const enableSubtitleUrl = async (url: string, label?: string) => {
    const generation = ++trackGeneration;
    const localPath = await downloadSubtitleToLocalPath(url, label);
    if (destroyed || generation !== trackGeneration) return;
    applyExternalSubtitle(localPath);
  };

  const prepareAndPlay = () => {
    if (destroyed) return;
    try {
      if (typeof avplay.prepareAsync === "function") {
        avplay.prepareAsync(
          () => {
            if (destroyed) return;
            ready = true;
            if (pendingSubtitle) {
              const next = pendingSubtitle;
              pendingSubtitle = null;
              void enableSubtitleUrl(next.url, next.label).catch((err) => {
                options.onError?.(err instanceof Error ? err.message : String(err));
              });
            }
            if (playWhenReady) safePlay();
          },
          (err) => options.onError?.(String(err)),
        );
      } else {
        avplay.prepare();
        ready = true;
        if (pendingSubtitle) {
          const next = pendingSubtitle;
          pendingSubtitle = null;
          void enableSubtitleUrl(next.url, next.label).catch((err) => {
            options.onError?.(err instanceof Error ? err.message : String(err));
          });
        }
        if (playWhenReady) safePlay();
      }
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  // Start silent until the app selects a track (matches HTML5 Off default).
  try {
    avplay.setSilentSubtitle?.(true);
  } catch {
    /* ignore */
  }

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
    setTextTrack: async (url, label) => {
      if (destroyed) return;
      trackGeneration += 1;
      if (!url) {
        pendingSubtitle = null;
        silent = true;
        clearSubtitleOverlay(overlay);
        try {
          avplay.setSilentSubtitle?.(true);
        } catch {
          /* ignore */
        }
        return;
      }

      if (!ready) {
        // Attach after prepare — setExternalSubtitlePath is most reliable then.
        pendingSubtitle = { url, label };
        return;
      }

      try {
        await enableSubtitleUrl(url, label);
      } catch (err) {
        options.onError?.(
          err instanceof Error ? err.message : "Could not load AVPlay subtitles",
        );
      }
    },
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      ready = false;
      playWhenReady = false;
      pendingSubtitle = null;
      trackGeneration += 1;
      destroySubtitleOverlay(overlay);
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
