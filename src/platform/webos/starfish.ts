/**
 * webOS native playback via HTML5 <video> + LG mediaOption / mediaPreferred.
 * This is the supported web-app path into the Starfish media pipeline — not the
 * private C++ StarfishMediaAPIs surface.
 *
 * @see https://webostv.developer.lge.com/develop/guides/mediaoption-parameter
 */

export interface StarfishPlayerHandle {
  element: HTMLVideoElement;
  play(): Promise<void>;
  pause(): void;
  destroy(): void;
  seekTo(seconds: number): void;
  getCurrentTime(): number;
  getDuration(): number;
  setTextTrack(url: string | null, label?: string): void;
}

export interface StarfishPlayerOptions {
  url: string;
  container: HTMLElement;
  autoplay?: boolean;
  mimeType?: string;
  preferNative?: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
  onTimeUpdate?: (currentSeconds: number, durationSeconds: number) => void;
}

export type StarfishStreamKind = "hls" | "mp4" | "other";

const HLS_MIME = "application/vnd.apple.mpegurl";
const MP4_MIME = "video/mp4";

/** Infer transport kind from an explicit MIME hint and/or URL. */
export function detectStarfishStreamKind(
  url: string,
  mimeType?: string | null,
): StarfishStreamKind {
  const mime = (mimeType ?? "").trim().toLowerCase();
  if (
    mime.includes("mpegurl") ||
    mime.includes("m3u8") ||
    mime === "application/vnd.apple.mpegurl" ||
    mime === "application/x-mpegurl"
  ) {
    return "hls";
  }
  if (mime.includes("mp4") || mime.includes("mpeg")) {
    return "mp4";
  }

  const path = url.split("?")[0]?.toLowerCase() ?? "";
  if (path.endsWith(".m3u8") || path.includes("/hls") || path.includes("master.m3u8")) {
    return "hls";
  }
  if (path.endsWith(".mp4") || path.endsWith(".m4v")) {
    return "mp4";
  }
  return "other";
}

/**
 * MIME type for the <source type="...;mediaOption=..."> attribute.
 * HLS must use an MPEG-URL type so webOS selects the HLS pipeline.
 */
export function resolveStarfishMimeType(url: string, mimeType?: string | null): string {
  const kind = detectStarfishStreamKind(url, mimeType);
  if (kind === "hls") return HLS_MIME;
  if (mimeType?.trim()) return mimeType.trim();
  if (kind === "mp4") return MP4_MIME;
  return MP4_MIME;
}

/**
 * LG mediaOption JSON. For HLS we set mediaTransportType=HLS and enable
 * adaptiveStreaming; progressive/direct uses URI.
 */
export function buildStarfishMediaOption(input: {
  preferNative: boolean;
  kind: StarfishStreamKind;
}): string | undefined {
  if (!input.preferNative) return undefined;

  if (input.kind === "hls") {
    return JSON.stringify({
      mediaTransportType: "HLS",
      option: {
        adaptiveStreaming: {
          adaptiveResolution: true,
          seamlessPlay: true,
          maxWidth: 3840,
          maxHeight: 2160,
        },
      },
      htmlMediaOption: {
        useUMSMediaInfo: true,
      },
    });
  }

  return JSON.stringify({
    mediaTransportType: "URI",
    htmlMediaOption: {
      useUMSMediaInfo: true,
    },
  });
}

export function isStarfishEnvironment(): boolean {
  if (typeof window === "undefined") return false;
  if (window.webOS?.platform?.tv) return true;
  if (typeof window.PalmSystem !== "undefined") return true;
  return /Web0S|webOS|LG Browser/i.test(navigator.userAgent);
}

export function createStarfishPlayer(options: StarfishPlayerOptions): StarfishPlayerHandle {
  const video = document.createElement("video");
  video.className = "prairie-video prairie-video--starfish";
  video.setAttribute("playsinline", "true");
  video.setAttribute("webkit-playsinline", "true");
  video.controls = false;
  video.preload = "auto";
  video.crossOrigin = "anonymous";
  video.style.width = "100%";
  video.style.height = "100%";
  video.style.objectFit = "contain";
  video.style.background = "#000";

  const preferNative = options.preferNative !== false;
  const kind = detectStarfishStreamKind(options.url, options.mimeType);
  const baseType = resolveStarfishMimeType(options.url, options.mimeType);
  const mediaOption = buildStarfishMediaOption({ preferNative, kind });

  const source = document.createElement("source");
  source.src = options.url;
  if (mediaOption) {
    source.setAttribute("type", `${baseType};mediaOption=${encodeURIComponent(mediaOption)}`);
    source.setAttribute("mediaOption", mediaOption);
    video.setAttribute("mediaPreferred", "true");
  } else {
    source.type = baseType;
  }

  video.appendChild(source);
  options.container.replaceChildren(video);

  const onError = () => {
    const err = video.error;
    options.onError?.(err ? `Media error ${err.code}` : "Playback failed");
  };
  const onEnded = () => options.onEnded?.();
  const onTimeUpdate = () => {
    options.onTimeUpdate?.(
      video.currentTime || 0,
      Number.isFinite(video.duration) ? video.duration : 0,
    );
  };
  video.addEventListener("error", onError);
  video.addEventListener("ended", onEnded);
  video.addEventListener("timeupdate", onTimeUpdate);

  if (options.autoplay !== false) {
    void video.play().catch((err: unknown) => {
      options.onError?.(err instanceof Error ? err.message : String(err));
    });
  }

  let activeTrack: HTMLTrackElement | null = null;

  return {
    element: video,
    play: () => video.play(),
    pause: () => video.pause(),
    seekTo: (seconds: number) => {
      if (Number.isFinite(seconds) && seconds >= 0) {
        video.currentTime = seconds;
      }
    },
    getCurrentTime: () => video.currentTime || 0,
    getDuration: () => (Number.isFinite(video.duration) ? video.duration : 0),
    setTextTrack: (url, label) => {
      if (activeTrack) {
        activeTrack.remove();
        activeTrack = null;
      }
      for (let i = 0; i < video.textTracks.length; i++) {
        video.textTracks[i]!.mode = "disabled";
      }
      if (!url) return;
      const track = document.createElement("track");
      track.kind = "subtitles";
      track.label = label ?? "Subtitles";
      track.src = url;
      track.default = true;
      video.appendChild(track);
      activeTrack = track;
      queueMicrotask(() => {
        if (track.track) track.track.mode = "showing";
      });
    },
    destroy: () => {
      video.removeEventListener("error", onError);
      video.removeEventListener("ended", onEnded);
      video.removeEventListener("timeupdate", onTimeUpdate);
      video.pause();
      source.removeAttribute("src");
      video.removeAttribute("src");
      video.load();
      video.remove();
    },
  };
}
