import { useEffect, useRef } from "react";
import {
  subtitleAppearanceCssVars,
  type SubtitleAppearance,
} from "../settings/subtitleAppearance";
import { createMediaPlayer } from "./createMediaPlayer";
import type { MediaPlayer } from "./types";
import type { ResolvedPlayerBackend } from "../platform/types";

interface PlayerHostProps {
  url: string;
  backend: ResolvedPlayerBackend;
  playing: boolean;
  mimeType?: string;
  subtitleAppearance?: SubtitleAppearance;
  onError?: (message: string) => void;
  onEnded?: () => void;
  onReady?: (player: MediaPlayer) => void;
  onTimeUpdate?: (currentSeconds: number, durationSeconds: number) => void;
}

function applySubtitleVars(
  el: HTMLElement,
  appearance: SubtitleAppearance | undefined,
): void {
  if (!appearance) return;
  const vars = subtitleAppearanceCssVars(appearance);
  for (const [key, value] of Object.entries(vars)) {
    el.style.setProperty(key, value);
  }
}

export function PlayerHost({
  url,
  backend,
  playing,
  mimeType,
  subtitleAppearance,
  onError,
  onEnded,
  onReady,
  onTimeUpdate,
}: PlayerHostProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<MediaPlayer | null>(null);
  const skipPlaySyncRef = useRef(false);
  const onTimeUpdateRef = useRef(onTimeUpdate);
  onTimeUpdateRef.current = onTimeUpdate;

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
        mimeType,
        onError,
        onEnded,
        onTimeUpdate: (current, duration) => onTimeUpdateRef.current?.(current, duration),
      });
    } catch (err) {
      onError?.(err instanceof Error ? err.message : String(err));
      return;
    }

    playerRef.current = player;
    skipPlaySyncRef.current = true;
    applySubtitleVars(container, subtitleAppearance);
    onReady?.(player);

    return () => {
      player.destroy();
      playerRef.current = null;
      container.replaceChildren();
    };
  }, [url, backend, mimeType]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    applySubtitleVars(container, subtitleAppearance);
  }, [subtitleAppearance]);

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
