import { deleteLocalSubtitleFile, downloadSubtitleToLocalPath } from "./downloadSubtitle";
import {
  clearSubtitleOverlay,
  createSubtitleOverlay,
  destroySubtitleOverlay,
  setSubtitleOverlayText,
} from "./subtitleOverlay";
import { pickExternalTextTrackIndex, type AvPlayTrackInfo } from "./avplayTracks";
import { avPlayFixedMaxResolution, probePanelMaxResolution } from "./displayResolution";
import { isHlsUrl, waitForHlsManifest } from "./waitForHlsManifest";

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
  setDisplayMethod?(displayMode: string): void;
  setStreamingProperty?(propertyType: string, propertyParam: string): void;
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
  onBuffering?: (active: boolean) => void;
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
  let seekInFlight = false;
  let pendingSeekMs: number | null = null;
  const allowedServerUrl = options.allowedServerUrl ?? null;

  const forgetLocalSubtitle = () => {
    if (activeLocalSubtitlePath) {
      deleteLocalSubtitleFile(activeLocalSubtitlePath);
      activeLocalSubtitlePath = null;
    }
  };

  claimInAppCaptions();

  // Samsung docs create an <object type="application/avplayer">; keep it transparent
  // so the hardware plane is not covered by an opaque widget.
  const avObject = document.createElement("object");
  avObject.type = "application/avplayer";
  avObject.setAttribute("aria-hidden", "true");
  Object.assign(avObject.style, {
    position: "absolute",
    left: "0",
    top: "0",
    width: "100%",
    height: "100%",
    background: "transparent",
    pointerEvents: "none",
  });
  options.container.appendChild(avObject);

  const overlay = createSubtitleOverlay(options.container);
  const hls = isHlsUrl(options.url);

  /** setDisplayRect uses the fixed 1920×1080 AVPlay coordinate space. */
  const fullscreenDisplayRect = () => ({ x: 0, y: 0, width: 1920, height: 1080 });

  const applyDisplay = () => {
    const display = fullscreenDisplayRect();
    avplay.setDisplayRect(display.x, display.y, display.width, display.height);
    try {
      avplay.setDisplayMethod?.("PLAYER_DISPLAY_MODE_LETTER_BOX");
    } catch {
      /* ignore */
    }
  };

  const applyIdleStreamingProps = () => {
    try {
      avplay.setStreamingProperty?.("USER_AGENT", "PrairieTizenClient");
    } catch {
      try {
        avplay.setStreamingProperty?.("USERAGENT", "PrairieTizenClient");
      } catch {
        /* older firmwares */
      }
    }
    if (hls) {
      try {
        // Keep in sync with probePanelMaxResolution() so a 4K panel is not
        // capped below what /playback/start advertised.
        const fixed = avPlayFixedMaxResolution(probePanelMaxResolution());
        avplay.setStreamingProperty?.(
          "ADAPTIVE_INFO",
          [
            `FIXED_MAX_RESOLUTION=${fixed}`,
            "STARTBITRATE=HIGHEST",
            "USER_AGENT=PrairieTizenClient",
            "INITIAL_BUFFER_DURATION=6000",
            "RESUME_BUFFER_DURATION=4000",
          ].join("|"),
        );
      } catch {
        /* ignore */
      }
    }
    try {
      (
        avplay as AvPlayApi & {
          setBufferingParam?: (a: string, b: string, c: number) => void;
        }
      ).setBufferingParam?.("PLAYER_BUFFER_FOR_PLAY", "PLAYER_BUFFER_SIZE_IN_SECOND", 6);
      (
        avplay as AvPlayApi & {
          setBufferingParam?: (a: string, b: string, c: number) => void;
        }
      ).setBufferingParam?.("PLAYER_BUFFER_FOR_RESUME", "PLAYER_BUFFER_SIZE_IN_SECOND", 4);
    } catch {
      /* ignore */
    }
  };

  let opened = false;
  const openSession = () => {
    if (destroyed || opened) return;
    opened = true;
    avplay.open(options.url);
    applyIdleStreamingProps();
    // Samsung sample order: open → setListener → setDisplayRect → prepareAsync.
    avplay.setListener({
      onbufferingstart: () => options.onBuffering?.(true),
      onbufferingcomplete: () => options.onBuffering?.(false),
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
    applyDisplay();
    try {
      avplay.setSilentSubtitle?.(true);
    } catch {
      /* ignore */
    }
  };

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

  const runSeek = (targetMs: number) => {
    seekInFlight = true;
    const onDone = () => {
      seekInFlight = false;
      if (destroyed) return;
      if (pendingSeekMs == null) return;
      const next = pendingSeekMs;
      pendingSeekMs = null;
      runSeek(next);
    };
    try {
      avplay.seekTo(targetMs, onDone, onDone);
    } catch (err) {
      seekInFlight = false;
      options.onError?.(err instanceof Error ? err.message : String(err));
    }
  };

  const onPrepared = () => {
    if (destroyed) return;
    ready = true;
    // Re-apply display after prepare — some firmwares reset it.
    try {
      applyDisplay();
    } catch {
      /* ignore */
    }
    if (pendingTrackSelect && overlayEnabled) {
      selectExternalTextTrack();
    }
    if (pendingSeekMs != null && !seekInFlight) {
      const targetMs = pendingSeekMs;
      pendingSeekMs = null;
      runSeek(targetMs);
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
   * Startup: wait for HLS playlist (remux/transcode), open AVPlay, attach
   * IDLE subtitles, then prepare. Direct play skips the manifest poll.
   */
  const beginStartup = () => {
    if (destroyed || prepareStarted) return;
    void (async () => {
      if (hls) {
        // preparePlayableSession already waited for the window-head segment;
        // this is a short safety poll for paths that hand AVPlay a URL without
        // that gate.
        const ready = await waitForHlsManifest(options.url, {
          timeoutMs: 15_000,
          requireSegment: true,
          throwOnTimeout: false,
        });
        if (destroyed) return;
        if (!ready) {
          options.onError?.("Transcode timed out");
          return;
        }
      }
      try {
        openSession();
      } catch (err) {
        options.onError?.(err instanceof Error ? err.message : String(err));
        return;
      }
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
      if (destroyed) return;
      const ms = Math.max(0, Math.floor(seconds * 1000));
      // Queue until READY so scrub is not dropped during prepare. Windowed
      // encoded resumes start at playlist entry 0 and need no client seek.
      if (!ready || seekInFlight) {
        pendingSeekMs = ms;
        return;
      }
      runSeek(ms);
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
      if (opened) {
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
      }
      avObject.remove();
    },
  };
}
