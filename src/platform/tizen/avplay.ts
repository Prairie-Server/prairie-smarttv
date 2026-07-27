import { deleteLocalSubtitleFile, downloadSubtitleToLocalPath } from "./downloadSubtitle";
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
  /** Preferred subtitle URL known at create time — attached in IDLE before prepare. */
  initialSubtitleUrl?: string | null;
  initialSubtitleLabel?: string;
  /** Connected Prairie origin — required for Tizen subtitle downloads. */
  allowedServerUrl?: string | null;
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
    // Keep the system caption surface off — we render via onsubtitlechange overlay.
    tvinfo?.showCaption?.(false);
  } catch {
    /* older firmwares */
  }
}

/**
 * Thin wrapper around Samsung AVPlay with full external-subtitle support:
 * download remote VTT/SRT/SMI → setExternalSubtitlePath (IDLE before prepare when
 * possible) → onsubtitlechange rendered in an HTML overlay so Prairie styling applies.
 *
 * Native AVPlay subtitle drawing stays silenced (`setSilentSubtitle(true)`); the
 * HTML overlay is the sole renderer so text/background settings work.
 */
export function createAvPlayPlayer(options: AvPlayPlayerOptions): AvPlayPlayerHandle {
  const avplay = getAvPlay();
  if (!avplay) {
    throw new Error("AVPlay is not available on this platform");
  }

  // Lifecycle state must exist before setListener — some bridges fire sync callbacks.
  let destroyed = false;
  let ready = false;
  let prepareStarted = false;
  let playWhenReady = options.autoplay !== false;
  /** Whether Prairie should show the HTML overlay (independent of AVPlay native silence). */
  let overlayEnabled = false;
  let trackGeneration = 0;
  let pendingSubtitle: { url: string; label?: string } | null = options.initialSubtitleUrl
    ? { url: options.initialSubtitleUrl, label: options.initialSubtitleLabel }
    : null;
  let activeDownloadCancel: (() => void) | null = null;
  let activeLocalSubtitlePath: string | null = null;
  let prepareTimer: number | null = null;
  /** True when an external path was set in IDLE and track select must wait for READY+. */
  let pendingTrackSelect = false;
  const allowedServerUrl = options.allowedServerUrl ?? null;

  const forgetLocalSubtitle = () => {
    if (activeLocalSubtitlePath) {
      deleteLocalSubtitleFile(activeLocalSubtitlePath);
      activeLocalSubtitlePath = null;
    }
  };

  claimInAppCaptions();

  // Samsung requires an <object type="application/avplayer"> display surface.
  // Without it, prepare/play can succeed while nothing is painted (blank chrome).
  const avObject = document.createElement("object");
  avObject.type = "application/avplayer";
  avObject.setAttribute("aria-hidden", "true");
  Object.assign(avObject.style, {
    position: "absolute",
    left: "0",
    top: "0",
    width: "100%",
    height: "100%",
    pointerEvents: "none",
  });
  options.container.appendChild(avObject);

  const overlay = createSubtitleOverlay(options.container);

  /**
   * setDisplayRect always uses a 1920×1080 coordinate space, regardless of
   * the app's CSS viewport (Samsung AVPlay guide).
   */
  const displayRectForContainer = () => {
    const rect = options.container.getBoundingClientRect();
    const clientWidth = Math.max(1, window.document.documentElement.clientWidth || window.innerWidth);
    const ratio = 1920 / clientWidth;
    return {
      x: Math.max(0, Math.floor(rect.left * ratio)),
      y: Math.max(0, Math.floor(rect.top * ratio)),
      width: Math.max(1, Math.floor((rect.width || clientWidth) * ratio)),
      height: Math.max(1, Math.floor((rect.height || window.innerHeight) * ratio)),
    };
  };

  avplay.open(options.url);
  // Samsung sample order: open → setListener → setDisplayRect → prepareAsync.
  avplay.setListener({
    onerror: (eventType) => options.onError?.(String(eventType)),
    onstreamcompleted: () => options.onEnded?.(),
    oncurrentplaytime: (currentTimeMs) => {
      let durationMs = 0;
      try {
        durationMs = avplay.getDuration();
      } catch {
        // keep durationMs at 0 when getDuration is unavailable
      }
      options.onTimeUpdate?.(currentTimeMs / 1000, durationMs / 1000);
    },
    onsubtitlechange: (_duration, text) => {
      if (destroyed || !overlayEnabled) {
        clearSubtitleOverlay(overlay);
        return;
      }
      setSubtitleOverlayText(overlay, text);
    },
  });
  const display = displayRectForContainer();
  avplay.setDisplayRect(display.x, display.y, display.width, display.height);

  // Always silence AVPlay's built-in caption renderer; we draw via the overlay.
  try {
    avplay.setSilentSubtitle?.(true);
  } catch {
    /* ignore */
  }

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

  const cancelActiveDownload = () => {
    activeDownloadCancel?.();
    activeDownloadCancel = null;
  };

  const avplayState = (): string => {
    try {
      return avplay.getState();
    } catch {
      return "";
    }
  };

  /** getTotalTrackInfo / setSelectTrack are only valid in READY / PLAYING / PAUSED. */
  const selectExternalTextTrack = () => {
    const state = avplayState();
    if (state !== "READY" && state !== "PLAYING" && state !== "PAUSED") {
      pendingTrackSelect = true;
      return;
    }
    pendingTrackSelect = false;
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

  const applyExternalSubtitlePath = (localPath: string) => {
    if (!avplay.setExternalSubtitlePath) {
      throw new Error("AVPlay setExternalSubtitlePath is unavailable on this firmware");
    }
    // Path attach is valid in IDLE (pre-prepare) and during playback.
    avplay.setExternalSubtitlePath(localPath);
    // Keep native drawing silenced — overlay handles presentation + styling.
    try {
      avplay.setSilentSubtitle?.(true);
    } catch {
      /* ignore */
    }
    overlayEnabled = true;
    selectExternalTextTrack();
  };

  const downloadAndApply = async (url: string, label?: string): Promise<void> => {
    const generation = ++trackGeneration;
    cancelActiveDownload();
    forgetLocalSubtitle();
    const handle = downloadSubtitleToLocalPath(url, label, { allowedServerUrl });
    activeDownloadCancel = handle.cancel;
    const localPath = await handle.promise;
    if (destroyed || generation !== trackGeneration) {
      deleteLocalSubtitleFile(localPath);
      return;
    }
    activeDownloadCancel = null;
    activeLocalSubtitlePath = localPath;
    applyExternalSubtitlePath(localPath);
  };

  const onPrepared = () => {
    if (destroyed) return;
    ready = true;
    if (pendingTrackSelect && overlayEnabled) {
      selectExternalTextTrack();
    }
    if (playWhenReady) safePlay();
  };

  const prepareAndPlay = () => {
    if (destroyed || prepareStarted) return;
    prepareStarted = true;
    try {
      if (typeof avplay.prepareAsync === "function") {
        avplay.prepareAsync(
          () => onPrepared(),
          (err) => options.onError?.(String(err)),
        );
      } else {
        avplay.prepare();
        onPrepared();
      }
    } catch (err) {
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  /**
   * Delay prepare one tick so PlayerHost.onReady → setTextTrack can queue a
   * pending subtitle, then attach it in IDLE before prepare (Samsung-recommended).
   * Drain pendingSubtitle in a loop so a newer selection during download is not lost.
   */
  const beginStartup = () => {
    if (destroyed || prepareStarted) return;
    void (async () => {
      while (pendingSubtitle && !destroyed) {
        const next = pendingSubtitle;
        pendingSubtitle = null;
        try {
          await downloadAndApply(next.url, next.label);
        } catch (err) {
          options.onError?.(err instanceof Error ? err.message : String(err));
        }
      }
      if (!destroyed) prepareAndPlay();
    })();
  };

  prepareTimer = window.setTimeout(beginStartup, 0);

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
      cancelActiveDownload();

      if (!url) {
        pendingSubtitle = null;
        pendingTrackSelect = false;
        overlayEnabled = false;
        forgetLocalSubtitle();
        clearSubtitleOverlay(overlay);
        try {
          avplay.setSilentSubtitle?.(true);
        } catch {
          /* ignore */
        }
        return;
      }

      if (!prepareStarted && !ready) {
        // Still in the pre-prepare window — attach in IDLE via beginStartup.
        pendingSubtitle = { url, label };
        return;
      }

      try {
        await downloadAndApply(url, label);
      } catch (err) {
        options.onError?.(err instanceof Error ? err.message : "Could not load AVPlay subtitles");
      }
    },
    destroy: () => {
      if (destroyed) return;
      destroyed = true;
      ready = false;
      playWhenReady = false;
      pendingSubtitle = null;
      pendingTrackSelect = false;
      overlayEnabled = false;
      trackGeneration += 1;
      cancelActiveDownload();
      forgetLocalSubtitle();
      if (prepareTimer != null) {
        window.clearTimeout(prepareTimer);
        prepareTimer = null;
      }
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
      avObject.remove();
    },
  };
}
