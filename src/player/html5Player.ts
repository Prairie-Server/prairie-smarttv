import type { CreateMediaPlayerOptions, MediaPlayer } from "./types";

export function createHtml5Player(options: CreateMediaPlayerOptions): MediaPlayer {
  const video = document.createElement("video");
  video.className = "prairie-video prairie-video--html5";
  video.setAttribute("playsinline", "true");
  video.controls = false;
  video.preload = "auto";
  video.crossOrigin = "anonymous";
  video.src = options.url;
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
    options.onTimeUpdate?.(video.currentTime || 0, Number.isFinite(video.duration) ? video.duration : 0);
  };
  video.addEventListener("error", onError);
  video.addEventListener("ended", onEnded);
  video.addEventListener("timeupdate", onTimeUpdate);
  options.container.replaceChildren(video);

  if (options.autoplay !== false) {
    void video.play().catch((err: unknown) => {
      options.onError?.(err instanceof Error ? err.message : String(err));
    });
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
      video.pause();
      video.removeAttribute("src");
      video.load();
      video.remove();
    },
  };
}
