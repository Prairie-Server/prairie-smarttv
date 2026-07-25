import type { CreateMediaPlayerOptions, MediaPlayer } from "./types";

export function createHtml5Player(options: CreateMediaPlayerOptions): MediaPlayer {
  const video = document.createElement("video");
  video.className = "prairie-video prairie-video--html5";
  video.setAttribute("playsinline", "true");
  video.controls = false;
  video.preload = "auto";
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
  video.addEventListener("error", onError);
  video.addEventListener("ended", onEnded);
  options.container.replaceChildren(video);

  if (options.autoplay !== false) {
    void video.play().catch((err: unknown) => {
      options.onError?.(err instanceof Error ? err.message : String(err));
    });
  }

  return {
    backend: "html5",
    play: () => video.play(),
    pause: () => video.pause(),
    destroy: () => {
      video.removeEventListener("error", onError);
      video.removeEventListener("ended", onEnded);
      video.pause();
      video.removeAttribute("src");
      video.load();
      video.remove();
    },
  };
}
