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
      onError: options.onError,
      onEnded: options.onEnded,
    });
    return {
      backend: "avplay",
      play: () => handle.play(),
      pause: () => handle.pause(),
      destroy: () => handle.destroy(),
    };
  }

  if (options.backend === "starfish") {
    const handle = createStarfishPlayer({
      url: options.url,
      container: options.container,
      autoplay: options.autoplay,
      preferNative: true,
      onError: options.onError,
      onEnded: options.onEnded,
    });
    return {
      backend: "starfish",
      play: () => handle.play(),
      pause: () => handle.pause(),
      destroy: () => handle.destroy(),
    };
  }

  return createHtml5Player(options);
}
