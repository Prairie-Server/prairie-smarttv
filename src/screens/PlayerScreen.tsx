import { ArrowLeft, Captions, FastForward, Pause, Play, Rewind, Volume2 } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "../api/client";
import {
  reportPlaybackProgress,
  stopPlaybackSession,
  switchPlaybackAudio,
} from "../api/playbackSession";
import { startPlayback } from "../api/startPlayback";
import { preparePlayableSession } from "../api/transcode";
import {
  fetchWatchDetail,
  formatAudioLabel,
  formatSubtitleLabel,
  selectFileVersion,
  type WatchDetail,
} from "../api/watch";
import { FocusButton } from "../components/FocusButton";
import { isActionableTarget } from "../focus/isActionableTarget";
import { subscribeBackKeys } from "../platform/backKey";
import { detectPlatform } from "../platform/detect";
import { resolveAdvertisedCapabilities } from "../platform/tizen/deviceCapabilities";
import { PlayerHost } from "../player/PlayerHost";
import { selectPlayerBackend } from "../player/createPlayer";
import { humanizePlaybackError } from "../player/humanizePlaybackError";
import { toMediaTime, toPlayerTime } from "../player/mediaTimeline";
import { filterClientRenderableSubtitles } from "../player/subtitleFormats";
import { formatPlaybackClock } from "../player/timeFormat";
import type { MediaPlayer, PlaybackSessionResponse, SubtitleUrlEntry } from "../player/types";
import {
  loadPlaybackSettings,
  resolveForcedPlayMethod,
  resolvePreferredSubtitleIndex,
  savePlaybackSettings,
} from "../settings/playbackSettings";
import type { PrairieSession } from "../storage/session";
import { buildStreamUrl } from "../api/client";

const PROGRESS_INTERVAL_MS = 10_000;
const SEEK_STEP_SECONDS = 15;
/** Delay before stopping the server session when the app is backgrounded. */
const BACKGROUND_STOP_GRACE_MS = 30_000;

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

function sourceResolutionForFile(
  detail: WatchDetail | null | undefined,
  fileId: number,
): string | undefined {
  if (!detail) return undefined;
  return (
    selectFileVersion(detail, fileId)?.resolution ?? detail.versions[0]?.resolution ?? undefined
  );
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
  const backgroundStopTimer = useRef<number | null>(null);
  /** Player-local seek after bootstrap; 0 for windowed encoded resume. */
  const pendingResumeRef = useRef<number | null>(null);
  /** Media-time origin of the current HLS window. */
  const streamOriginRef = useRef(0);
  const activeSubtitleIndexRef = useRef(-1);
  const exitedRef = useRef(false);
  const hlsFallbackTriedRef = useRef(false);
  const fallingBackRef = useRef(false);
  const reanchoringRef = useRef(false);
  const seekByRef = useRef<(delta: number) => void>(() => undefined);
  const bumpControlsRef = useRef<() => void>(() => undefined);
  const handleExitRef = useRef<() => Promise<void>>(async () => undefined);

  const deviceCaps = useMemo(
    () =>
      resolveAdvertisedCapabilities({
        forceAv1: settings.forceAv1,
        disableAv1: settings.disableAv1,
      }),
    [settings.forceAv1, settings.disableAv1],
  );

  const [playback, setPlayback] = useState<PlaybackSessionResponse | null>(null);
  const [streamUrl, setStreamUrl] = useState<string | null>(null);
  const [watch, setWatch] = useState<WatchDetail | null>(launch.watch ?? null);
  const [playing, setPlaying] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [buffering, setBuffering] = useState(false);
  const [currentTime, setCurrentTime] = useState(launch.startPositionSeconds ?? 0);
  const [duration, setDuration] = useState(0);
  const [menu, setMenu] = useState<MenuMode>("none");
  const [activeSubtitleIndex, setActiveSubtitleIndex] = useState(-1);
  const [busyAudio, setBusyAudio] = useState(false);
  const [controlsVisible, setControlsVisible] = useState(true);

  const audioTracks = useMemo(() => {
    if (!watch || !playback) return [];
    const version = selectFileVersion(watch, playback.media_file_id) ?? watch.versions[0] ?? null;
    return version?.audio_tracks ?? [];
  }, [watch, playback]);

  const subtitleTracks = useMemo(
    () => filterClientRenderableSubtitles(playback?.subtitle_urls ?? []),
    [playback?.subtitle_urls],
  );

  useEffect(() => {
    playbackRef.current = playback;
  }, [playback]);

  useEffect(() => {
    activeSubtitleIndexRef.current = activeSubtitleIndex;
  }, [activeSubtitleIndex]);

  useEffect(() => {
    return () => {
      if (hideTimer.current != null) window.clearTimeout(hideTimer.current);
      if (backgroundStopTimer.current != null) window.clearTimeout(backgroundStopTimer.current);
    };
  }, []);

  // Clear opaque app backgrounds so the AVPlay plane shows through.
  useEffect(() => {
    const root = document.documentElement;
    root.classList.add("player-active");
    document.body.classList.add("player-active");
    return () => {
      root.classList.remove("player-active");
      document.body.classList.remove("player-active");
    };
  }, []);

  function clearPlayerActive(): void {
    document.documentElement.classList.remove("player-active");
    document.body.classList.remove("player-active");
  }

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      setBuffering(false);
      hlsFallbackTriedRef.current = false;
      pendingResumeRef.current = null;
      streamOriginRef.current = 0;
      try {
        let watchDetail = launch.watch ?? null;
        if (!watchDetail && launch.contentId) {
          watchDetail = await fetchWatchDetail(session, launch.contentId);
          if (!cancelled) setWatch(watchDetail);
        }
        // Advertise probed codecs and let Prairie choose Direct / Remux(+AAC) /
        // Transcode. Do not force full video transcode just because audio is TrueHD.
        const forced = resolveForcedPlayMethod(settings);
        const started = await startPlayback(session, {
          fileId: launch.fileId,
          profileId: session.profileId,
          forcedPlayMethod: forced,
          startPosition: launch.startPositionSeconds,
          codecsVideo: deviceCaps.codecs_video,
          codecsAudio: deviceCaps.codecs_audio,
          containers: deviceCaps.containers,
          maxResolution: deviceCaps.max_resolution,
          hdr: deviceCaps.hdr,
        });
        if (cancelled) {
          // StrictMode remount / abandon — stop the orphaned session so AVPlay
          // does not open a stream that the server already tore down.
          void stopPlaybackSession(session, started.session_id).catch(() => undefined);
          return;
        }
        // Remux/transcode need /playback/transcode/start → manifest_url (web/mobile parity).
        const seekAt = launch.startPositionSeconds ?? started.position ?? 0;
        let prepared;
        try {
          prepared = await preparePlayableSession(session, started, seekAt, {
            sourceResolution: sourceResolutionForFile(watchDetail, started.media_file_id),
            maxResolution: deviceCaps.max_resolution,
          });
        } catch (prepErr) {
          void stopPlaybackSession(session, started.session_id).catch(() => undefined);
          throw prepErr;
        }
        if (cancelled) {
          void stopPlaybackSession(session, prepared.session.session_id).catch(() => undefined);
          return;
        }
        setPlayback(prepared.session);
        setStreamUrl(prepared.streamUrl);
        streamOriginRef.current = prepared.streamOriginSeconds;
        pendingResumeRef.current =
          prepared.playerStartSeconds > 0 ? prepared.playerStartSeconds : null;
        setCurrentTime(
          toMediaTime(prepared.playerStartSeconds, prepared.streamOriginSeconds) || seekAt,
        );
        setPlaying(true);
        if (prepared.session.duration_seconds) setDuration(prepared.session.duration_seconds);
      } catch (err) {
        if (cancelled) return;
        if (err instanceof ApiError) setError(humanizePlaybackError(err.message));
        else if (err instanceof Error) setError(humanizePlaybackError(err.message));
        else setError("Playback failed to start");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [
    launch.fileId,
    launch.contentId,
    launch.startPositionSeconds,
    launch.watch,
    session,
    settings,
    deviceCaps,
  ]);

  // Do not DELETE the playback session on React effect cleanup / StrictMode
  // remount — that races AVPlay and surfaces PLAYER_ERR_CONNECTION_FAILED.
  // Sessions are stopped only via handleExit (Back / error dismiss).

  useEffect(() => {
    return subscribeBackKeys((event) => {
      event.preventDefault?.();
      void handleExitRef.current();
    });
  }, []);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const key = event.key;
      if (error) return;
      if (key === "Enter" || key === " " || key === "MediaPlayPause") {
        if (menu !== "none") return;
        // OK/Enter on a chrome button must activate that button — not play/pause.
        if (
          (key === "Enter" || key === " ") &&
          (isActionableTarget(event.target) || isActionableTarget(document.activeElement))
        ) {
          return;
        }
        event.preventDefault();
        setPlaying((p) => !p);
        bumpControlsRef.current();
        return;
      }
      if (key === "MediaRewind" || (key === "ArrowLeft" && event.altKey)) {
        event.preventDefault();
        seekByRef.current(-SEEK_STEP_SECONDS);
        return;
      }
      if (key === "MediaFastForward" || (key === "ArrowRight" && event.altKey)) {
        event.preventDefault();
        seekByRef.current(SEEK_STEP_SECONDS);
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [menu, error]);

  function bumpControls() {
    if (error) {
      setControlsVisible(true);
      return;
    }
    setControlsVisible(true);
    if (hideTimer.current != null) window.clearTimeout(hideTimer.current);
    // Keep chrome up while the stream is still preparing.
    if (loading || !streamUrl) return;
    hideTimer.current = window.setTimeout(() => {
      setMenu((m) => {
        if (m === "none") setControlsVisible(false);
        return m;
      });
    }, 4000);
  }

  // Start the auto-hide clock once playback is ready. Without this the chrome
  // stays up forever after launch (controlsVisible defaults to true).
  useEffect(() => {
    if (loading || error || !streamUrl) return;
    bumpControls();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only re-arm when readiness changes
  }, [loading, error, streamUrl]);

  async function forceHlsFallback(reason: string): Promise<boolean> {
    if (exitedRef.current || hlsFallbackTriedRef.current || fallingBackRef.current) return false;
    const current = playbackRef.current;
    const method = current?.play_method.trim().toLowerCase() ?? "";
    // Already on a full encode ladder — surface the error instead of looping.
    if (!current || method === "transcode") return false;
    hlsFallbackTriedRef.current = true;
    fallingBackRef.current = true;
    setLoading(true);
    setError(null);
    setBuffering(false);
    setControlsVisible(true);
    const seekAt =
      toMediaTime(playerRef.current?.getCurrentTime() ?? 0, streamOriginRef.current) || currentTime;
    const oldSid = current.session_id;
    try {
      await stopPlaybackSession(session, oldSid).catch(() => undefined);
      if (exitedRef.current) return false;
      const started = await startPlayback(session, {
        fileId: launch.fileId,
        profileId: session.profileId,
        forcedPlayMethod: "transcode",
        startPosition: seekAt,
        codecsVideo: deviceCaps.codecs_video,
        codecsAudio: deviceCaps.codecs_audio,
        containers: deviceCaps.containers,
        maxResolution: deviceCaps.max_resolution,
        hdr: deviceCaps.hdr,
      });
      const prepared = await preparePlayableSession(session, started, seekAt, {
        sourceResolution: sourceResolutionForFile(watch, started.media_file_id),
        maxResolution: deviceCaps.max_resolution,
      });
      if (exitedRef.current) {
        void stopPlaybackSession(session, prepared.session.session_id).catch(() => undefined);
        return false;
      }
      setPlayback(prepared.session);
      setStreamUrl(prepared.streamUrl);
      streamOriginRef.current = prepared.streamOriginSeconds;
      pendingResumeRef.current =
        prepared.playerStartSeconds > 0 ? prepared.playerStartSeconds : null;
      setCurrentTime(
        toMediaTime(prepared.playerStartSeconds, prepared.streamOriginSeconds) || seekAt,
      );
      setPlaying(true);
      if (prepared.session.duration_seconds) setDuration(prepared.session.duration_seconds);
      return true;
    } catch {
      if (exitedRef.current) return false;
      setError(humanizePlaybackError(reason));
      setPlaying(false);
      setControlsVisible(false);
      return false;
    } finally {
      fallingBackRef.current = false;
      setLoading(false);
    }
  }

  function handlePlaybackError(message: string) {
    if (exitedRef.current) return;
    const current = playbackRef.current;
    const method = current?.play_method.trim().toLowerCase() ?? "";
    if ((method === "direct" || method === "remux") && !hlsFallbackTriedRef.current) {
      void forceHlsFallback(message);
      return;
    }
    setBuffering(false);
    setError(humanizePlaybackError(message));
    setPlaying(false);
    setControlsVisible(false);
    if (hideTimer.current != null) {
      window.clearTimeout(hideTimer.current);
      hideTimer.current = null;
    }
  }

  async function retryPlayback() {
    if (exitedRef.current) return;
    setError(null);
    setLoading(true);
    setBuffering(false);
    setControlsVisible(true);
    try {
      const forced = resolveForcedPlayMethod(settings);
      const seekAt = currentTime > 0 ? currentTime : (launch.startPositionSeconds ?? 0);
      const oldSid = playbackRef.current?.session_id;
      if (oldSid) {
        await stopPlaybackSession(session, oldSid).catch(() => undefined);
      }
      if (exitedRef.current) return;
      const started = await startPlayback(session, {
        fileId: launch.fileId,
        profileId: session.profileId,
        forcedPlayMethod: forced,
        startPosition: seekAt,
        codecsVideo: deviceCaps.codecs_video,
        codecsAudio: deviceCaps.codecs_audio,
        containers: deviceCaps.containers,
        maxResolution: deviceCaps.max_resolution,
        hdr: deviceCaps.hdr,
      });
      const prepared = await preparePlayableSession(session, started, seekAt, {
        sourceResolution: sourceResolutionForFile(watch, started.media_file_id),
        maxResolution: deviceCaps.max_resolution,
      });
      if (exitedRef.current) {
        void stopPlaybackSession(session, prepared.session.session_id).catch(() => undefined);
        return;
      }
      setPlayback(prepared.session);
      setStreamUrl(prepared.streamUrl);
      streamOriginRef.current = prepared.streamOriginSeconds;
      pendingResumeRef.current =
        prepared.playerStartSeconds > 0 ? prepared.playerStartSeconds : null;
      setCurrentTime(
        toMediaTime(prepared.playerStartSeconds, prepared.streamOriginSeconds) || seekAt,
      );
      setPlaying(true);
      if (prepared.session.duration_seconds) setDuration(prepared.session.duration_seconds);
    } catch (err) {
      if (exitedRef.current) return;
      if (err instanceof ApiError) setError(humanizePlaybackError(err.message));
      else if (err instanceof Error) setError(humanizePlaybackError(err.message));
      else setError("Playback failed to start");
    } finally {
      setLoading(false);
    }
  }

  function mediaPositionSeconds(): number {
    const player = playerRef.current;
    if (!player) return currentTime;
    return toMediaTime(player.getCurrentTime(), streamOriginRef.current);
  }

  async function reportProgress(force = false, isPaused = !playing) {
    const sid = playbackRef.current?.session_id;
    if (!sid) return;
    const now = Date.now();
    if (!force && now - lastProgressAt.current < PROGRESS_INTERVAL_MS) return;
    lastProgressAt.current = now;
    const position = mediaPositionSeconds();
    try {
      await reportPlaybackProgress(session, sid, position, isPaused);
    } catch {
      /* best-effort */
    }
  }

  async function handleExit() {
    if (exitedRef.current) return;
    exitedRef.current = true;
    if (backgroundStopTimer.current != null) {
      window.clearTimeout(backgroundStopTimer.current);
      backgroundStopTimer.current = null;
    }
    if (hideTimer.current != null) {
      window.clearTimeout(hideTimer.current);
      hideTimer.current = null;
    }
    // Restore opaque backgrounds before navigating. If Back also backgrounds the
    // packaged app (unhandled tizenhwkey), a lingering player-active class left
    // only the TV wallpaper / empty shell visible.
    clearPlayerActive();
    // Navigate first so we never sit on a transparent player plane / body gradient
    // while awaiting network teardown.
    const sid = playbackRef.current?.session_id;
    const position = mediaPositionSeconds();
    playbackRef.current = null;
    onExit();
    void (async () => {
      if (sid) {
        try {
          await reportPlaybackProgress(session, sid, position, true);
        } catch {
          /* best-effort */
        }
        await stopPlaybackSession(session, sid).catch(() => undefined);
      }
    })();
  }

  // After BACKGROUND_STOP_GRACE_MS hidden, report progress and stop the session.
  useEffect(() => {
    function onVisibility() {
      if (document.visibilityState === "hidden") {
        if (backgroundStopTimer.current != null) return;
        backgroundStopTimer.current = window.setTimeout(() => {
          backgroundStopTimer.current = null;
          void (async () => {
            await reportProgress(true, true);
            const sid = playbackRef.current?.session_id;
            if (sid && !exitedRef.current) {
              await stopPlaybackSession(session, sid).catch(() => undefined);
              playbackRef.current = null;
            }
          })();
        }, BACKGROUND_STOP_GRACE_MS);
        return;
      }
      if (backgroundStopTimer.current != null) {
        window.clearTimeout(backgroundStopTimer.current);
        backgroundStopTimer.current = null;
      }
    }
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- session stable for this mount
  }, [session]);

  /** Re-plan the HLS window at a media-time target (seek before window head). */
  async function reanchorAtMediaTime(mediaSeconds: number) {
    const current = playbackRef.current;
    if (!current || reanchoringRef.current || exitedRef.current) return;
    reanchoringRef.current = true;
    setLoading(true);
    setError(null);
    setBuffering(true);
    const oldSid = current.session_id;
    try {
      await stopPlaybackSession(session, oldSid).catch(() => undefined);
      if (exitedRef.current) return;
      const forced =
        current.play_method.trim().toLowerCase() === "transcode"
          ? "transcode"
          : resolveForcedPlayMethod(settings);
      const started = await startPlayback(session, {
        fileId: launch.fileId,
        profileId: session.profileId,
        forcedPlayMethod: forced,
        startPosition: mediaSeconds,
        codecsVideo: deviceCaps.codecs_video,
        codecsAudio: deviceCaps.codecs_audio,
        containers: deviceCaps.containers,
        maxResolution: deviceCaps.max_resolution,
        hdr: deviceCaps.hdr,
      });
      const prepared = await preparePlayableSession(session, started, mediaSeconds, {
        sourceResolution: sourceResolutionForFile(watch, started.media_file_id),
        maxResolution: deviceCaps.max_resolution,
      });
      if (exitedRef.current) {
        void stopPlaybackSession(session, prepared.session.session_id).catch(() => undefined);
        return;
      }
      setPlayback(prepared.session);
      setStreamUrl(prepared.streamUrl);
      streamOriginRef.current = prepared.streamOriginSeconds;
      pendingResumeRef.current =
        prepared.playerStartSeconds > 0 ? prepared.playerStartSeconds : null;
      setCurrentTime(
        toMediaTime(prepared.playerStartSeconds, prepared.streamOriginSeconds) || mediaSeconds,
      );
      setPlaying(true);
      if (prepared.session.duration_seconds) setDuration(prepared.session.duration_seconds);
    } catch (err) {
      if (exitedRef.current) return;
      if (err instanceof ApiError) setError(humanizePlaybackError(err.message));
      else if (err instanceof Error) setError(humanizePlaybackError(err.message));
      else setError("Could not seek");
    } finally {
      reanchoringRef.current = false;
      setLoading(false);
      setBuffering(false);
    }
  }

  function seekBy(delta: number) {
    bumpControls();
    const player = playerRef.current;
    if (!player || reanchoringRef.current) return;
    const mediaNext = Math.max(0, mediaPositionSeconds() + delta);
    const playerNext = toPlayerTime(mediaNext, streamOriginRef.current);
    if (playerNext < 0) {
      // Before the current window — Jellyfin/Plex-style seek = new manifest.
      void reanchorAtMediaTime(mediaNext);
      return;
    }
    void player.seekTo(playerNext);
    setCurrentTime(mediaNext);
    void reportProgress(true);
  }

  useEffect(() => {
    seekByRef.current = seekBy;
    bumpControlsRef.current = bumpControls;
    handleExitRef.current = handleExit;
  });

  async function chooseAudio(index: number) {
    const sid = playbackRef.current?.session_id;
    const current = playbackRef.current;
    if (!sid || !current || busyAudio) return;
    setBusyAudio(true);
    setError(null);
    try {
      const position = mediaPositionSeconds();
      const updated = await switchPlaybackAudio(session, sid, index, position);
      const nextSession: PlaybackSessionResponse = {
        ...current,
        stream_url: updated.stream_url,
        play_method: updated.play_method,
        audio_track_index: updated.audio_track_index,
        position,
      };
      const seekAt = position;
      const prepared = await preparePlayableSession(session, nextSession, seekAt, {
        sourceResolution: sourceResolutionForFile(watch, nextSession.media_file_id),
        maxResolution: deviceCaps.max_resolution,
      });
      setPlayback(prepared.session);
      streamOriginRef.current = prepared.streamOriginSeconds;
      pendingResumeRef.current =
        prepared.playerStartSeconds > 0 ? prepared.playerStartSeconds : null;
      setCurrentTime(
        toMediaTime(prepared.playerStartSeconds, prepared.streamOriginSeconds) || seekAt,
      );
      setStreamUrl(prepared.streamUrl);
      setMenu("none");
      bumpControls();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not switch audio");
    } finally {
      setBusyAudio(false);
    }
  }

  function applySubtitleIndex(index: number, player: MediaPlayer | null = playerRef.current) {
    setActiveSubtitleIndex(index);
    activeSubtitleIndexRef.current = index;
    if (!player) return;
    if (index < 0) {
      void player.setTextTrack(null);
      return;
    }
    const track = subtitleTracks[index];
    if (track) {
      void player.setTextTrack(
        resolveSubtitleUrl(session.serverUrl, session.accessToken, track),
        formatSubtitleLabel(track),
      );
    }
  }

  function chooseSubtitle(index: number) {
    applySubtitleIndex(index);
    const language = index < 0 ? "" : (subtitleTracks[index]?.language ?? "").toLowerCase();
    savePlaybackSettings({
      ...loadPlaybackSettings(),
      preferredSubtitleLanguage: language,
    });
    setMenu("none");
    bumpControls();
  }

  // Seed for AVPlay IDLE attach — only recomputed when the stream changes, not on
  // every mid-play Subs menu pick (those use setTextTrack).
  const streamSubtitleSeed = useMemo(() => {
    const preferred = resolvePreferredSubtitleIndex(
      subtitleTracks,
      settings.preferredSubtitleLanguage,
    );
    const index = activeSubtitleIndexRef.current >= 0 ? activeSubtitleIndexRef.current : preferred;
    if (index < 0) {
      return { url: null as string | null, label: undefined as string | undefined, index: -1 };
    }
    const track = subtitleTracks[index];
    if (!track) return { url: null, label: undefined, index: -1 };
    return {
      url: resolveSubtitleUrl(session.serverUrl, session.accessToken, track),
      label: formatSubtitleLabel(track),
      index,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- seed tied to stream identity
  }, [
    streamUrl,
    subtitleTracks,
    settings.preferredSubtitleLanguage,
    session.serverUrl,
    session.accessToken,
  ]);

  const progressPct = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0;
  const title = launch.title?.trim() || watch?.title || `File ${launch.fileId}`;
  const streamMimeType = useMemo(() => {
    const streamType = (playback?.playback_info?.stream_type ?? "").toLowerCase();
    if (streamType === "hls" || streamUrl?.includes(".m3u8")) {
      return "application/vnd.apple.mpegurl";
    }
    if (streamType === "mp4" || streamUrl?.includes(".mp4")) {
      return "video/mp4";
    }
    return undefined;
  }, [playback?.playback_info?.stream_type, streamUrl]);

  return (
    <section
      className={`screen player-screen${backend === "html5" ? " player-screen--html5" : ""}`}
    >
      {streamUrl ? (
        <PlayerHost
          key={streamUrl}
          url={streamUrl}
          backend={backend}
          playing={playing && !error}
          mimeType={streamMimeType}
          subtitleAppearance={settings.subtitleAppearance}
          initialSubtitleUrl={streamSubtitleSeed.url}
          initialSubtitleLabel={streamSubtitleSeed.label}
          allowedServerUrl={session.serverUrl}
          onError={handlePlaybackError}
          onBuffering={(active) => {
            if (!error) setBuffering(active);
          }}
          onReady={(player) => {
            playerRef.current = player;
            setBuffering(false);
            // Windowed encoded resumes start at playlist entry 0 — no client seek.
            // Only apply a player-local offset when the server asked for one
            // (e.g. remux keyframe snap inside the window).
            const resume = pendingResumeRef.current;
            pendingResumeRef.current = null;
            if (resume != null && resume > 0) {
              void player.seekTo(resume);
              setCurrentTime(toMediaTime(resume, streamOriginRef.current));
            }
            // Re-sync selection after every player recreate (e.g. audio switch).
            const index =
              activeSubtitleIndexRef.current >= 0
                ? activeSubtitleIndexRef.current
                : streamSubtitleSeed.index;
            if (index >= 0) {
              applySubtitleIndex(index, player);
            } else {
              void player.setTextTrack(null);
            }
          }}
          onTimeUpdate={(time, dur) => {
            if (error || reanchoringRef.current) return;
            setCurrentTime(toMediaTime(time, streamOriginRef.current));
            // Prefer the server media runtime; player duration is window-local.
            if (dur > 0 && streamOriginRef.current <= 0 && !playback?.duration_seconds) {
              setDuration(dur);
            }
            void reportProgress(false);
          }}
        />
      ) : null}

      {buffering && !error && !loading ? (
        <div className="player-buffering" aria-live="polite">
          <p className="player-buffering__label">Buffering…</p>
        </div>
      ) : null}

      {error ? (
        <div className="player-error" role="alertdialog" aria-labelledby="player-error-title">
          <div className="player-error__dialog">
            <p className="eyebrow">Playback error</p>
            <h1 id="player-error-title">{title}</h1>
            <p className="form-error">{error}</p>
            <div className="player-error__actions">
              <FocusButton autoFocus icon={<Play />} onClick={() => void retryPlayback()}>
                Try again
              </FocusButton>
              <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={() => void handleExit()}>
                Back to title
              </FocusButton>
            </div>
          </div>
        </div>
      ) : controlsVisible || menu !== "none" ? (
        <div className="player-chrome" onMouseMove={bumpControls}>
          <div className="player-top-bar">
            <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={() => void handleExit()}>
              Back
            </FocusButton>
            <div className="player-meta">
              <p className="eyebrow">Now playing</p>
              <h1>{title}</h1>
              <p className="muted">
                {backend === "avplay"
                  ? "TV player"
                  : backend === "starfish"
                    ? "LG player"
                    : "Browser"}
                {playback?.play_method === "direct"
                  ? " · Direct"
                  : playback?.play_method === "remux"
                    ? " · Remux"
                    : playback?.play_method === "transcode"
                      ? " · Transcode"
                      : ""}
                {loading ? " · Preparing…" : buffering ? " · Buffering…" : ""}
              </p>
            </div>
          </div>

          <div className="player-chrome__bottom">
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
                icon={<Rewind />}
                onClick={() => seekBy(-SEEK_STEP_SECONDS)}
                disabled={!streamUrl}
              >
                −15s
              </FocusButton>
              <FocusButton
                autoFocus
                icon={playing ? <Pause /> : <Play />}
                onClick={() => {
                  setPlaying((p) => {
                    const next = !p;
                    if (!next) void reportProgress(true, true);
                    return next;
                  });
                  bumpControls();
                }}
                disabled={!streamUrl}
              >
                {playing ? "Pause" : "Play"}
              </FocusButton>
              <FocusButton
                variant="ghost"
                icon={<FastForward />}
                onClick={() => seekBy(SEEK_STEP_SECONDS)}
                disabled={!streamUrl}
              >
                +15s
              </FocusButton>
              {audioTracks.length > 0 ? (
                <FocusButton
                  variant="ghost"
                  icon={<Volume2 />}
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
                  icon={<Captions />}
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

            <p className="hint muted">OK toggles play · −15s / +15s seek · Back exits</p>
          </div>
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
