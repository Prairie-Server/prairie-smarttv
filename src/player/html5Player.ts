// Runtime resolves to the light build via the Vite alias in vite.config.ts —
// full typings, ~35% smaller than the default bundle.
import Hls, { Events as HlsEvents, ErrorTypes as HlsErrorTypes } from "hls.js";
import { resolveHtml5Source, TV_HLS_CONFIG } from "./hlsSource";
import type { CreateMediaPlayerOptions, MediaPlayer } from "./types";

export function createHtml5Player(options: CreateMediaPlayerOptions): MediaPlayer {
  const video = document.createElement("video");
  video.className = "prairie-video prairie-video--html5";
  video.setAttribute("playsinline", "true");
  video.controls = false;
  video.preload = "auto";
  video.crossOrigin = "anonymous";
  video.style.width = "100%";
  video.style.height = "100%";
  video.style.objectFit = "contain";
  video.style.background = "#000";

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
  options.container.replaceChildren(video);

  const autoplay = options.autoplay !== false;
  const startPlayback = () => {
    if (!autoplay) return;
    void video.play().catch((err: unknown) => {
      options.onError?.(err instanceof Error ? err.message : String(err));
    });
  };

  const sourceKind = resolveHtml5Source({
    url: options.url,
    mimeType: options.mimeType,
    nativeHlsSupport: video.canPlayType("application/vnd.apple.mpegurl"),
    hlsJsSupported: Hls.isSupported(),
  });

  let hls: Hls | null = null;

  if (sourceKind === "hls-js") {
    hls = new Hls(TV_HLS_CONFIG);
    // Recovery is attempted once per failure class; a second failure of the same
    // kind is reported so the UI shows an error instead of buffering forever.
    let mediaRecoveryUsed = false;
    let networkRecoveryUsed = false;

    hls.on(HlsEvents.MANIFEST_PARSED, () => startPlayback());

    hls.on(HlsEvents.ERROR, (_event, data) => {
      if (!data.fatal) return;
      if (data.type === HlsErrorTypes.MEDIA_ERROR && !mediaRecoveryUsed) {
        mediaRecoveryUsed = true;
        hls?.recoverMediaError();
        return;
      }
      if (data.type === HlsErrorTypes.NETWORK_ERROR && !networkRecoveryUsed) {
        networkRecoveryUsed = true;
        hls?.startLoad();
        return;
      }
      const detail = data.details ? ` (${data.details})` : "";
      options.onError?.(`Could not load stream${detail}`);
    });

    hls.loadSource(options.url);
    hls.attachMedia(video);
  } else {
    video.src = options.url;
    startPlayback();
  }

  let activeTrack: HTMLTrackElement | null = null;

  return {
    backend: "html5",
    play: () => video.play(),
    pause: () => video.pause(),
    seekTo: (seconds: number) => {
      if (Number.isFinite(seconds) && seconds >= 0) {
        video.currentTime = seconds;
      }
    },
    getCurrentTime: () => video.currentTime || 0,
    getDuration: () => (Number.isFinite(video.duration) ? video.duration : 0),
    // External WebVTT is a <track> on the same element, which works whether or
    // not hls.js owns the media source.
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
      // Enable after the browser registers the track.
      queueMicrotask(() => {
        if (track.track) track.track.mode = "showing";
      });
    },
    destroy: () => {
      video.removeEventListener("error", onError);
      video.removeEventListener("ended", onEnded);
      video.removeEventListener("timeupdate", onTimeUpdate);
      // Destroy hls.js first: it stops segment fetching and frees the MSE
      // buffers, which matters on low-memory TV hardware across repeat plays.
      if (hls) {
        hls.destroy();
        hls = null;
      }
      video.pause();
      video.removeAttribute("src");
      video.load();
      video.remove();
    },
  };
}
