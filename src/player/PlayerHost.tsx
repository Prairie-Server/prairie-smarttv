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
  /** Preferred/selected external subtitle for AVPlay IDLE attach. */
  initialSubtitleUrl?: string | null;
  initialSubtitleLabel?: string;
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
  initialSubtitleUrl,
  initialSubtitleLabel,
  onError,
  onEnded,
  onReady,
  onTimeUpdate,
}: PlayerHostProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<MediaPlayer | null>(null);
  const skipPlaySyncRef = useRef(false);
  const onTimeUpdateRef = useRef(onTimeUpdate);
  const onErrorRef = useRef(onError);
  const onEndedRef = useRef(onEnded);
  const onReadyRef = useRef(onReady);
  onTimeUpdateRef.current = onTimeUpdate;
  onErrorRef.current = onError;
  onEndedRef.current = onEnded;
  onReadyRef.current = onReady;

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
        initialSubtitleUrl,
        initialSubtitleLabel,
        onError: (message) => onErrorRef.current?.(message),
        onEnded: () => onEndedRef.current?.(),
        onTimeUpdate: (current, duration) => onTimeUpdateRef.current?.(current, duration),
      });
    } catch (err) {
      onErrorRef.current?.(err instanceof Error ? err.message : String(err));
      return;
    }

    playerRef.current = player;
    skipPlaySyncRef.current = true;
    applySubtitleVars(container, subtitleAppearance);
    onReadyRef.current?.(player);

    return () => {
      player.destroy();
      playerRef.current = null;
      container.replaceChildren();
    };
    // Recreate only when the stream identity changes. Subtitle selection mid-play
    // uses setTextTrack; initialSubtitle* is consumed at create for AVPlay IDLE attach.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- intentional create-once-per-stream
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
