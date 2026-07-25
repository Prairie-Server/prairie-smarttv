/**
 * webOS "Starfish-style" playback: HTML5 <video> with LG mediaOption /
 * mediaPreferred hints when the platform understands them.
 *
 * This is intentionally not a copy of any third-party player stack — it is a
 * minimal adapter that prefers native decoding paths on LG TV webviews.
 */

export interface StarfishPlayerHandle {
  element: HTMLVideoElement;
  play(): Promise<void>;
  pause(): void;
  destroy(): void;
}

export interface StarfishPlayerOptions {
  url: string;
  container: HTMLElement;
  autoplay?: boolean;
  mimeType?: string;
  /** Prefer native media pipeline on webOS when supported. */
  preferNative?: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
}

function buildMediaOption(preferNative: boolean): string | undefined {
  if (!preferNative) return undefined;
  // LG documents mediaOption / mediaPreferred as JSON attached to <source>.
  // Keep the payload minimal and defensive — unknown keys are ignored.
  return JSON.stringify({
    htmlMediaOption: {
      useUMSMediaInfo: true,
    },
    mediaTransportType: "URI",
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
  video.style.width = "100%";
  video.style.height = "100%";
  video.style.objectFit = "contain";
  video.style.background = "#000";

  const preferNative = options.preferNative !== false;
  const mediaOption = buildMediaOption(preferNative);
  const source = document.createElement("source");
  source.src = options.url;
  if (options.mimeType) source.type = options.mimeType;
  if (mediaOption) {
    source.setAttribute("type", options.mimeType ?? "video/mp4;mediaOption=" + encodeURIComponent(mediaOption));
    // Dual-signal: some webOS builds read attributes; others read dataset.
    source.setAttribute("mediaOption", mediaOption);
    video.setAttribute("mediaPreferred", "true");
  }

  video.appendChild(source);
  options.container.replaceChildren(video);

  const onError = () => {
    const err = video.error;
    options.onError?.(err ? `Media error ${err.code}` : "Playback failed");
  };
  const onEnded = () => options.onEnded?.();
  video.addEventListener("error", onError);
  video.addEventListener("ended", onEnded);

  if (options.autoplay !== false) {
    void video.play().catch((err: unknown) => {
      options.onError?.(err instanceof Error ? err.message : String(err));
    });
  }

  return {
    element: video,
    play: () => video.play(),
    pause: () => video.pause(),
    destroy: () => {
      video.removeEventListener("error", onError);
      video.removeEventListener("ended", onEnded);
      video.pause();
      source.removeAttribute("src");
      video.removeAttribute("src");
      video.load();
      video.remove();
    },
  };
}
