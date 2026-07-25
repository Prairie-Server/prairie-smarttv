import { useEffect, useMemo, useState } from "react";
import { startPlayback, resolvePlaybackStreamUrl } from "../api/startPlayback";
import { ApiError } from "../api/client";
import { detectPlatform } from "../platform/detect";
import { PlayerHost } from "../player/PlayerHost";
import { selectPlayerBackend } from "../player/createPlayer";
import {
  loadPlaybackSettings,
  resolveForcedPlayMethod,
} from "../settings/playbackSettings";
import type { PrairieSession } from "../storage/session";
import { FocusButton } from "../components/FocusButton";

interface PlayerScreenProps {
  session: PrairieSession;
  fileId: number;
  title?: string;
  onExit: () => void;
}

export function PlayerScreen({ session, fileId, title, onExit }: PlayerScreenProps) {
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

  const [streamUrl, setStreamUrl] = useState<string | null>(null);
  const [playMethod, setPlayMethod] = useState<string | null>(null);
  const [playing, setPlaying] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const forced = resolveForcedPlayMethod(settings);
        const sessionResp = await startPlayback(session.serverUrl, session.accessToken, {
          fileId,
          profileId: session.profileId,
          forcedPlayMethod: forced,
        });
        if (cancelled) return;
        setPlayMethod(sessionResp.play_method);
        setStreamUrl(
          resolvePlaybackStreamUrl(session.serverUrl, sessionResp, session.accessToken),
        );
        setPlaying(true);
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ApiError) setError(err.message);
        else if (err instanceof Error) setError(err.message);
        else setError("Playback failed to start");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [fileId, session, settings]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const key = event.key;
      // OK / Enter toggles play; Back / Escape exits (destroys native player via unmount).
      if (key === "Enter" || key === " " || key === "MediaPlayPause") {
        event.preventDefault();
        setPlaying((p) => !p);
        return;
      }
      if (
        key === "Escape" ||
        key === "Backspace" ||
        key === "XF86Back" ||
        key === "BrowserBack" ||
        // Tizen / webOS numeric key codes sometimes surface as "GoBack"
        key === "GoBack"
      ) {
        event.preventDefault();
        onExit();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onExit]);

  return (
    <section className="screen player-screen">
      {streamUrl && !error ? (
        <PlayerHost
          url={streamUrl}
          backend={backend}
          playing={playing}
          onError={setError}
        />
      ) : null}

      <div className="player-chrome">
        <div className="player-meta">
          <p className="eyebrow">Now playing</p>
          <h1>{title?.trim() || `File ${fileId}`}</h1>
          <p className="muted">
            Backend: {backend}
            {playMethod ? ` · ${playMethod}` : ""}
            {loading ? " · starting…" : ""}
            {title ? ` · file ${fileId}` : ""}
          </p>
        </div>
        {error ? <p className="form-error" role="alert">{error}</p> : null}
        <div className="player-controls">
          <FocusButton
            autoFocus
            onClick={() => setPlaying((p) => !p)}
            disabled={!streamUrl || Boolean(error)}
          >
            {playing ? "Pause" : "Play"}
          </FocusButton>
          <FocusButton variant="ghost" onClick={onExit}>
            Back
          </FocusButton>
        </div>
        <p className="hint muted">OK toggles play/pause · Back exits and destroys the player</p>
      </div>
    </section>
  );
}
