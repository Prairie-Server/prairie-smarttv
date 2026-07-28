import { ArrowLeft, Pause, Play, Square } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "../api/client";
import {
  channelDisplayLabel,
  playableLiveUrl,
  releaseLiveTvSession,
  resolveLivePlaybackUrl,
  startLiveTvSession,
  type LiveTvChannel,
} from "../api/livetv";
import { FocusButton } from "../components/FocusButton";
import { isActionableTarget } from "../focus/isActionableTarget";
import { subscribeBackKeys } from "../platform/backKey";
import { detectPlatform } from "../platform/detect";
import { PlayerHost } from "../player/PlayerHost";
import { selectPlayerBackend } from "../player/createPlayer";
import { loadPlaybackSettings } from "../settings/playbackSettings";
import type { PrairieSession } from "../storage/session";

interface LiveTvPlayerScreenProps {
  session: PrairieSession;
  channel: LiveTvChannel;
  onExit: () => void;
}

export function LiveTvPlayerScreen({ session, channel, onExit }: LiveTvPlayerScreenProps) {
  const settings = useMemo(() => loadPlaybackSettings(), []);
  const platform = useMemo(() => detectPlatform(), []);
  const backend = useMemo(
    () =>
      selectPlayerBackend({
        preference: settings.playerBackend,
        platform,
      }),
    [settings.playerBackend, platform],
  );

  const liveSessionId = useRef<string | null>(null);
  const playerRef = useRef<{ pause: () => void; destroy: () => void } | null>(null);
  const exitedRef = useRef(false);
  const handleExitRef = useRef<() => Promise<void>>(async () => undefined);
  const [streamUrl, setStreamUrl] = useState<string | null>(null);
  const [playing, setPlaying] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    const root = document.documentElement;
    root.classList.add("player-active");
    document.body.classList.add("player-active");
    return () => {
      root.classList.remove("player-active");
      document.body.classList.remove("player-active");
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const started = await startLiveTvSession(session, channel.id);
        if (cancelled) {
          await releaseLiveTvSession(session, started.session_id).catch(() => undefined);
          return;
        }
        liveSessionId.current = started.session_id;
        const raw = playableLiveUrl(started);
        if (!raw) throw new Error("Live TV session returned no stream URL");
        setStreamUrl(
          resolveLivePlaybackUrl(session.serverUrl, raw, session.accessToken, session.profileId),
        );
        setNote(started.note ?? null);
        setPlaying(true);
      } catch (err) {
        if (!cancelled) {
          if (err instanceof ApiError) setError(err.message);
          else if (err instanceof Error) setError(err.message);
          else setError("Could not start Live TV");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      const sid = liveSessionId.current;
      if (sid && !exitedRef.current) {
        void releaseLiveTvSession(session, sid).catch(() => undefined);
      }
    };
  }, [session, channel.id]);

  useEffect(() => {
    return subscribeBackKeys((event) => {
      event.preventDefault?.();
      void handleExitRef.current();
    });
  }, []);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const key = event.key;
      if (key === "Enter" || key === " " || key === "MediaPlayPause") {
        if (
          (key === "Enter" || key === " ") &&
          (isActionableTarget(event.target) || isActionableTarget(document.activeElement))
        ) {
          return;
        }
        event.preventDefault();
        setPlaying((p) => !p);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const handleExit = useCallback(async () => {
    if (exitedRef.current) return;
    exitedRef.current = true;
    const sid = liveSessionId.current;
    liveSessionId.current = null;
    try {
      playerRef.current?.pause();
    } catch {
      /* ignore */
    }
    try {
      playerRef.current?.destroy();
    } catch {
      /* ignore */
    }
    playerRef.current = null;
    document.documentElement.classList.remove("player-active");
    document.body.classList.remove("player-active");
    // Navigate first — never await network on a transparent player plane.
    onExit();
    if (sid) {
      void releaseLiveTvSession(session, sid).catch(() => undefined);
    }
  }, [session, onExit]);

  useEffect(() => {
    handleExitRef.current = handleExit;
  }, [handleExit]);

  return (
    <section className="screen player-screen">
      {streamUrl && !error ? (
        <PlayerHost
          url={streamUrl}
          backend={backend}
          playing={playing}
          onError={setError}
          onReady={(player) => {
            playerRef.current = player;
          }}
        />
      ) : null}

      <div className="player-chrome">
        <div className="player-top-bar">
          <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={() => void handleExit()}>
            Back
          </FocusButton>
          <div className="player-meta">
            <p className="eyebrow">Live TV</p>
            <h1>{channelDisplayLabel(channel)}</h1>
            <p className="muted">
              Ch {channel.number_override || channel.number}
              {channel.hd ? " · HD" : ""}
              {loading ? " · tuning…" : " · live"}
              {note ? ` · ${note}` : ""}
            </p>
          </div>
        </div>
        <div className="player-controls">
          <FocusButton
            autoFocus
            icon={playing ? <Pause /> : <Play />}
            onClick={() => setPlaying((p) => !p)}
            disabled={!streamUrl || Boolean(error)}
          >
            {playing ? "Pause" : "Play"}
          </FocusButton>
          <FocusButton variant="ghost" icon={<Square />} onClick={() => void handleExit()}>
            Stop
          </FocusButton>
        </div>
        {error ? (
          <p className="form-error" role="alert">
            {error}
          </p>
        ) : null}
        <p className="hint muted">Live sessions are released when you leave this screen</p>
      </div>
    </section>
  );
}
