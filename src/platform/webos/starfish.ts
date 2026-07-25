/**
 * webOS "Starfish-style" playback: HTML5 <video> with LG mediaOption /
 * mediaPreferred hints when the platform understands them.
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

function buildMediaOption(preferNative: boolean): string | undefined {
  if (!preferNative) return undefined;
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
  video.crossOrigin = "anonymous";
  video.style.width = "100%";
  video.style.height = "100%";
  video.style.objectFit = "contain";
  video.style.background = "#000";

  const preferNative = options.preferNative !== false;
  const mediaOption = buildMediaOption(preferNative);
  const source = document.createElement("source");
  source.src = options.url;
  if (mediaOption) {
    const baseType = options.mimeType ?? "video/mp4";
    source.setAttribute("type", `${baseType};mediaOption=${encodeURIComponent(mediaOption)}`);
    source.setAttribute("mediaOption", mediaOption);
    video.setAttribute("mediaPreferred", "true");
  } else if (options.mimeType) {
    source.type = options.mimeType;
  }

  video.appendChild(source);
  options.container.replaceChildren(video);

  const onError = () => {
    const err = video.error;
    options.onError?.(err ? `Media error ${err.code}` : "Playback failed");
  };
  const onEnded = () => options.onEnded?.();
  const onTimeUpdate = () => {
    options.onTimeUpdate?.(video.currentTime || 0, Number.isFinite(video.duration) ? video.duration : 0);
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
