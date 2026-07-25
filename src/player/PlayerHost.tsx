import { useEffect, useRef } from "react";
import { createMediaPlayer } from "./createMediaPlayer";
import type { MediaPlayer } from "./types";
import type { ResolvedPlayerBackend } from "../platform/types";

interface PlayerHostProps {
  url: string;
  backend: ResolvedPlayerBackend;
  playing: boolean;
  onError?: (message: string) => void;
  onEnded?: () => void;
  onReady?: (player: MediaPlayer) => void;
}

export function PlayerHost({
  url,
  backend,
  playing,
  onError,
  onEnded,
  onReady,
}: PlayerHostProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<MediaPlayer | null>(null);
  // Creation already honors `playing` via autoplay — skip the first sync tick.
  const skipPlaySyncRef = useRef(false);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    let player: MediaPlayer;
    try {
      player = createMediaPlayer({
        url,
        container,
        backend,
        autoplay: playing,
        onError,
        onEnded,
      });
    } catch (err) {
      onError?.(err instanceof Error ? err.message : String(err));
      return;
    }

    playerRef.current = player;
    skipPlaySyncRef.current = true;
    onReady?.(player);

    return () => {
      player.destroy();
      playerRef.current = null;
      container.replaceChildren();
    };
  }, [url, backend]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player) return;
    if (skipPlaySyncRef.current) {
      skipPlaySyncRef.current = false;
      return;
    }
    if (playing) {
      void player.play();
    } else {
      player.pause();
    }
  }, [playing]);

  return <div className="player-host" ref={containerRef} aria-label="Video player" />;
}
