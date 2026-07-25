import { createAvPlayPlayer } from "../platform/tizen/avplay";
import { createStarfishPlayer } from "../platform/webos/starfish";
import { createHtml5Player } from "./html5Player";
import type { CreateMediaPlayerOptions, MediaPlayer } from "./types";

export function createMediaPlayer(options: CreateMediaPlayerOptions): MediaPlayer {
  if (options.backend === "avplay") {
    const handle = createAvPlayPlayer({
      url: options.url,
      container: options.container,
      autoplay: options.autoplay,
      initialSubtitleUrl: options.initialSubtitleUrl,
      initialSubtitleLabel: options.initialSubtitleLabel,
      onError: options.onError,
      onEnded: options.onEnded,
      onTimeUpdate: options.onTimeUpdate,
    });
    return {
      backend: "avplay",
      play: () => handle.play(),
      pause: () => handle.pause(),
      destroy: () => handle.destroy(),
      seekTo: (seconds) => handle.seekTo(seconds),
      getCurrentTime: () => handle.getCurrentTime(),
      getDuration: () => handle.getDuration(),
      setTextTrack: (url, label) => handle.setTextTrack(url, label),
    };
  }

  if (options.backend === "starfish") {
    const handle = createStarfishPlayer({
      url: options.url,
      container: options.container,
      autoplay: options.autoplay,
      preferNative: true,
      mimeType: options.mimeType,
      onError: options.onError,
      onEnded: options.onEnded,
      onTimeUpdate: options.onTimeUpdate,
    });
    return {
      backend: "starfish",
      play: () => handle.play(),
      pause: () => handle.pause(),
      destroy: () => handle.destroy(),
      seekTo: (seconds) => handle.seekTo(seconds),
      getCurrentTime: () => handle.getCurrentTime(),
      getDuration: () => handle.getDuration(),
      setTextTrack: (url, label) => handle.setTextTrack(url, label),
    };
  }

  return createHtml5Player(options);
}
