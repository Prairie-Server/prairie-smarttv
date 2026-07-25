import { useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "../api/client";
import {
  reportPlaybackProgress,
  stopPlaybackSession,
  switchPlaybackAudio,
} from "../api/playbackSession";
import { startPlayback, resolvePlaybackStreamUrl } from "../api/startPlayback";
import {
  fetchWatchDetail,
  formatAudioLabel,
  formatSubtitleLabel,
  selectFileVersion,
  type WatchDetail,
} from "../api/watch";
import { FocusButton } from "../components/FocusButton";
import { detectPlatform } from "../platform/detect";
import { PlayerHost } from "../player/PlayerHost";
import { selectPlayerBackend } from "../player/createPlayer";
import { formatPlaybackClock } from "../player/timeFormat";
import type { MediaPlayer, PlaybackSessionResponse, SubtitleUrlEntry } from "../player/types";
import {
  loadPlaybackSettings,
  resolveForcedPlayMethod,
} from "../settings/playbackSettings";
import type { PrairieSession } from "../storage/session";
import { buildStreamUrl } from "../api/client";

const PROGRESS_INTERVAL_MS = 10_000;
const SEEK_STEP_SECONDS = 15;

export interface PlayerLaunch {
  fileId: number;
  title?: string;
  contentId?: string;
  startPositionSeconds?: number;
  watch?: WatchDetail | null;
}

interface PlayerScreenProps {
  session: PrairieSession;
  launch: PlayerLaunch;
  onExit: () => void;
}

type MenuMode = "none" | "audio" | "subs";

function resolveSubtitleUrl(
  serverUrl: string,
  accessToken: string,
  track: SubtitleUrlEntry,
): string {
  return buildStreamUrl(serverUrl, track.url, accessToken);
}

export function PlayerScreen({ session, launch, onExit }: PlayerScreenProps) {
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

  const playerRef = useRef<MediaPlayer | null>(null);
  const playbackRef = useRef<PlaybackSessionResponse | null>(null);
  const lastProgressAt = useRef(0);
  const hideTimer = useRef<number | null>(null);
  const exitedRef = useRef(false);

  const [playback, setPlayback] = useState<PlaybackSessionResponse | null>(null);
  const [streamUrl, setStreamUrl] = useState<string | null>(null);
  const [watch, setWatch] = useState<WatchDetail | null>(launch.watch ?? null);
  const [playing, setPlaying] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [currentTime, setCurrentTime] = useState(launch.startPositionSeconds ?? 0);
  const [duration, setDuration] = useState(0);
  const [menu, setMenu] = useState<MenuMode>("none");
  const [activeSubtitleIndex, setActiveSubtitleIndex] = useState(-1);
  const [busyAudio, setBusyAudio] = useState(false);
  const [controlsVisible, setControlsVisible] = useState(true);
  const [resumeApplied, setResumeApplied] = useState(false);

  const audioTracks = useMemo(() => {
    if (!watch || !playback) return [];
    const version =
      selectFileVersion(watch, playback.media_file_id) ?? watch.versions[0] ?? null;
    return version?.audio_tracks ?? [];
  }, [watch, playback]);

  const subtitleTracks = playback?.subtitle_urls ?? [];

  useEffect(() => {
    playbackRef.current = playback;
  }, [playback]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      setResumeApplied(false);
      try {
        if (!launch.watch && launch.contentId) {
          const detail = await fetchWatchDetail(session, launch.contentId);
          if (!cancelled) setWatch(detail);
        }
        const forced = resolveForcedPlayMethod(settings);
        const started = await startPlayback(session.serverUrl, session.accessToken, {
          fileId: launch.fileId,
          profileId: session.profileId,
          forcedPlayMethod: forced,
          startPosition: launch.startPositionSeconds,
        });
        if (cancelled) return;
        setPlayback(started);
        setStreamUrl(
          resolvePlaybackStreamUrl(session.serverUrl, started, session.accessToken),
        );
        setPlaying(true);
        if (started.duration_seconds) setDuration(started.duration_seconds);
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
  }, [launch.fileId, launch.contentId, launch.startPositionSeconds, launch.watch, session, settings]);

  useEffect(() => {
    return () => {
      const sid = playbackRef.current?.session_id;
      if (!sid || exitedRef.current) return;
      void stopPlaybackSession(session, sid).catch(() => undefined);
    };
  }, [session]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const key = event.key;
      if (key === "Enter" || key === " " || key === "MediaPlayPause") {
        if (menu !== "none") return;
        event.preventDefault();
        setPlaying((p) => !p);
        bumpControls();
        return;
      }
      if (key === "MediaRewind" || (key === "ArrowLeft" && event.altKey)) {
        event.preventDefault();
        seekBy(-SEEK_STEP_SECONDS);
        return;
      }
      if (key === "MediaFastForward" || (key === "ArrowRight" && event.altKey)) {
        event.preventDefault();
        seekBy(SEEK_STEP_SECONDS);
        return;
      }
      if (
        key === "Escape" ||
        key === "Backspace" ||
        key === "XF86Back" ||
        key === "BrowserBack" ||
        key === "GoBack"
      ) {
        event.preventDefault();
        void handleExit();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [menu, playback]);

  function bumpControls() {
    setControlsVisible(true);
    if (hideTimer.current != null) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => {
      setMenu((m) => {
        if (m === "none") setControlsVisible(false);
        return m;
      });
    }, 4000);
  }

  async function reportProgress(force = false, isPaused = !playing) {
    const sid = playbackRef.current?.session_id;
    if (!sid) return;
    const now = Date.now();
    if (!force && now - lastProgressAt.current < PROGRESS_INTERVAL_MS) return;
    lastProgressAt.current = now;
    const position = playerRef.current?.getCurrentTime() ?? currentTime;
    try {
      await reportPlaybackProgress(session, sid, position, isPaused);
    } catch {
      /* best-effort */
    }
  }

  async function handleExit() {
    if (exitedRef.current) return;
    exitedRef.current = true;
    await reportProgress(true, true);
    const sid = playbackRef.current?.session_id;
    if (sid) {
      await stopPlaybackSession(session, sid).catch(() => undefined);
    }
    onExit();
  }

  function seekBy(delta: number) {
    bumpControls();
    const player = playerRef.current;
    if (!player) return;
    const next = Math.max(0, player.getCurrentTime() + delta);
    void player.seekTo(next);
    setCurrentTime(next);
    void reportProgress(true);
  }

  async function chooseAudio(index: number) {
    const sid = playbackRef.current?.session_id;
    if (!sid || busyAudio) return;
    setBusyAudio(true);
    setError(null);
    try {
      const position = playerRef.current?.getCurrentTime() ?? currentTime;
      const updated = await switchPlaybackAudio(session, sid, index, position);
      setPlayback((prev) =>
        prev
          ? {
              ...prev,
              stream_url: updated.stream_url,
              play_method: updated.play_method,
              audio_track_index: updated.audio_track_index,
              position,
            }
          : prev,
      );
      setStreamUrl(
        resolvePlaybackStreamUrl(
          session.serverUrl,
          {
            ...(playbackRef.current as PlaybackSessionResponse),
            stream_url: updated.stream_url,
            play_method: updated.play_method,
            audio_track_index: updated.audio_track_index,
          },
          session.accessToken,
        ),
      );
      setResumeApplied(false);
      setMenu("none");
      bumpControls();
      // Resume near the same position after stream reload.
      window.setTimeout(() => {
        const target = updated.player_start_seconds ?? position;
        void playerRef.current?.seekTo(target);
        setCurrentTime(target);
        setResumeApplied(true);
      }, 450);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not switch audio");
    } finally {
      setBusyAudio(false);
    }
  }

  function chooseSubtitle(index: number) {
    setActiveSubtitleIndex(index);
    const player = playerRef.current;
    if (!player) return;
    if (index < 0) {
      void player.setTextTrack(null);
    } else {
      const track = subtitleTracks[index];
      if (track) {
        void player.setTextTrack(
          resolveSubtitleUrl(session.serverUrl, session.accessToken, track),
          formatSubtitleLabel(track),
        );
      }
    }
    setMenu("none");
    bumpControls();
  }

  const progressPct = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0;
  const title = launch.title?.trim() || watch?.title || `File ${launch.fileId}`;

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
            const resume = launch.startPositionSeconds ?? 0;
            if (!resumeApplied && resume > 0) {
              void player.seekTo(resume);
              setCurrentTime(resume);
              setResumeApplied(true);
            }
          }}
          onTimeUpdate={(time, dur) => {
            setCurrentTime(time);
            if (dur > 0) setDuration(dur);
            void reportProgress(false);
          }}
        />
      ) : null}

      {controlsVisible || menu !== "none" ? (
        <div className="player-chrome" onMouseMove={bumpControls}>
          <div className="player-top-bar">
            <FocusButton variant="ghost" onClick={() => void handleExit()}>
              Back
            </FocusButton>
            <div className="player-meta">
              <p className="eyebrow">Now playing</p>
              <h1>{title}</h1>
              <p className="muted">
                {backend}
                {playback?.play_method ? ` · ${playback.play_method}` : ""}
                {loading ? " · starting…" : ""}
              </p>
            </div>
          </div>

          <div className="player-scrub">
            <div className="player-scrub-track">
              <div className="player-scrub-fill" style={{ width: `${progressPct}%` }} />
            </div>
            <div className="player-time-row">
              <span>{formatPlaybackClock(currentTime)}</span>
              <span>{formatPlaybackClock(duration)}</span>
            </div>
          </div>

          <div className="player-controls">
            <FocusButton
              variant="ghost"
              onClick={() => seekBy(-SEEK_STEP_SECONDS)}
              disabled={!streamUrl || Boolean(error)}
            >
              −15s
            </FocusButton>
            <FocusButton
              autoFocus
              onClick={() => {
                setPlaying((p) => {
                  const next = !p;
                  if (!next) void reportProgress(true, true);
                  return next;
                });
                bumpControls();
              }}
              disabled={!streamUrl || Boolean(error)}
            >
              {playing ? "Pause" : "Play"}
            </FocusButton>
            <FocusButton
              variant="ghost"
              onClick={() => seekBy(SEEK_STEP_SECONDS)}
              disabled={!streamUrl || Boolean(error)}
            >
              +15s
            </FocusButton>
            {audioTracks.length > 0 ? (
              <FocusButton
                variant="ghost"
                onClick={() => {
                  setMenu((m) => (m === "audio" ? "none" : "audio"));
                  bumpControls();
                }}
              >
                Audio
              </FocusButton>
            ) : null}
            {subtitleTracks.length > 0 ? (
              <FocusButton
                variant="ghost"
                onClick={() => {
                  setMenu((m) => (m === "subs" ? "none" : "subs"));
                  bumpControls();
                }}
              >
                Subs
              </FocusButton>
            ) : null}
          </div>

          {menu === "audio" ? (
            <div className="player-menu" role="menu">
              <p className="eyebrow">Audio tracks</p>
              {audioTracks.map((track, index) => (
                <FocusButton
                  key={`a-${index}`}
                  variant={playback?.audio_track_index === index ? "primary" : "ghost"}
                  className="player-menu__item"
                  onClick={() => void chooseAudio(index)}
                  disabled={busyAudio}
                >
                  {formatAudioLabel(track, index)}
                  {playback?.audio_track_index === index ? " ✓" : ""}
                  {busyAudio ? " …" : ""}
                </FocusButton>
              ))}
            </div>
          ) : null}

          {menu === "subs" ? (
            <div className="player-menu" role="menu">
              <p className="eyebrow">Subtitles</p>
              <FocusButton
                variant={activeSubtitleIndex < 0 ? "primary" : "ghost"}
                className="player-menu__item"
                onClick={() => chooseSubtitle(-1)}
              >
                Off{activeSubtitleIndex < 0 ? " ✓" : ""}
              </FocusButton>
              {subtitleTracks.map((track, index) => (
                <FocusButton
                  key={`s-${index}`}
                  variant={activeSubtitleIndex === index ? "primary" : "ghost"}
                  className="player-menu__item"
                  onClick={() => chooseSubtitle(index)}
                >
                  {formatSubtitleLabel(track)}
                  {activeSubtitleIndex === index ? " ✓" : ""}
                </FocusButton>
              ))}
            </div>
          ) : null}

          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <p className="hint muted">OK toggles play · −15s / +15s seek · Back exits</p>
        </div>
      ) : (
        <button
          type="button"
          className="player-tap-catcher"
          onClick={bumpControls}
          aria-label="Show controls"
        />
      )}
    </section>
  );
}
