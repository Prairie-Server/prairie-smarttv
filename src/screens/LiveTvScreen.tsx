import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Circle, Play, X } from "lucide-react";
import { ApiError } from "../api/client";
import {
  cancelLiveTvRecording,
  channelDisplayLabel,
  currentProgramInIndex,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  fetchLiveTvRecordings,
  nextProgramInIndex,
  indexProgramsByChannel,
  scheduleLiveTvRecording,
  type LiveTvChannel,
  type LiveTvProgram,
  type LiveTvRecording,
} from "../api/livetv";
import { FocusButton } from "../components/FocusButton";
import type { PrairieSession } from "../storage/session";

interface LiveTvScreenProps {
  session: PrairieSession;
  onTune: (channel: LiveTvChannel) => void;
}

type LiveTvTab = "guide" | "channels" | "recordings";

function formatGuideClock(iso: string): string {
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return "";
  return new Date(ms).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
}

function programLine(program: LiveTvProgram | null, fallback: string): string {
  if (!program) return fallback;
  const when = [formatGuideClock(program.start), formatGuideClock(program.stop)]
    .filter(Boolean)
    .join(" – ");
  return when ? `${program.title} · ${when}` : program.title;
}

function formatRecordingWindow(recording: LiveTvRecording): string {
  const start = formatGuideClock(recording.start);
  const stop = formatGuideClock(recording.stop);
  return [start, stop].filter(Boolean).join(" – ");
}

function recordingStatusLabel(status: string): string {
  const normalized = status.trim().toLowerCase();
  if (normalized === "scheduled") return "Scheduled";
  if (normalized === "recording") return "Recording";
  if (normalized === "completed") return "Completed";
  if (normalized === "failed") return "Failed";
  if (normalized === "cancelled") return "Cancelled";
  return status.trim() || "Unknown";
}

function canCancelRecording(recording: LiveTvRecording): boolean {
  const status = recording.status.trim().toLowerCase();
  return status === "scheduled" || status === "recording";
}

export function LiveTvScreen({ session, onTune }: LiveTvScreenProps) {
  const [channels, setChannels] = useState<LiveTvChannel[]>([]);
  const [programs, setPrograms] = useState<LiveTvProgram[]>([]);
  // Group + sort the guide once per fetch instead of per channel row per render.
  const guideIndex = useMemo(() => indexProgramsByChannel(programs), [programs]);
  const [recordings, setRecordings] = useState<LiveTvRecording[]>([]);
  const [loading, setLoading] = useState(true);
  const [recordingsLoading, setRecordingsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<LiveTvTab>("guide");
  // Track which program is scheduling so only that row shows "Scheduling…".
  // Every Record button still disables while one request is in flight: the
  // synchronous guard below rejects a second one anyway, and on a remote a
  // button that silently does nothing reads as a dead app.
  const [recordingBusyId, setRecordingBusyId] = useState<string | null>(null);
  const [cancelBusyId, setCancelBusyId] = useState<string | null>(null);
  const [recordingMessage, setRecordingMessage] = useState<{
    kind: "success" | "error";
    text: string;
  } | null>(null);
  const recordingMessageTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  /** Synchronous guard — React state alone cannot stop double-submit. */
  const recordingInFlight = useRef(false);
  const cancelInFlight = useRef(false);

  useEffect(() => {
    return () => {
      if (recordingMessageTimer.current) clearTimeout(recordingMessageTimer.current);
    };
  }, []);

  function showRecordingMessage(kind: "success" | "error", text: string) {
    if (recordingMessageTimer.current) clearTimeout(recordingMessageTimer.current);
    setRecordingMessage({ kind, text });
    if (kind === "success") {
      recordingMessageTimer.current = setTimeout(() => setRecordingMessage(null), 4000);
    }
  }

  function scheduleRecordingErrorMessage(err: unknown): string {
    if (err instanceof ApiError) {
      if (err.status === 403) return "Not allowed to schedule recordings";
      if (err.status === 404) return "Program not found";
      if (err.status === 409) return "Recording already scheduled";
    }
    return "Could not schedule recording";
  }

  function cancelRecordingErrorMessage(err: unknown): string {
    if (err instanceof ApiError) {
      if (err.status === 403) return "Not allowed to cancel recordings";
      if (err.status === 404) return "Recording not found";
    }
    return "Could not cancel recording";
  }

  const refreshRecordings = useCallback(async () => {
    setRecordingsLoading(true);
    try {
      const list = await fetchLiveTvRecordings(session);
      setRecordings(list);
    } catch (err) {
      showRecordingMessage(
        "error",
        err instanceof ApiError ? err.message : "Could not load recordings",
      );
    } finally {
      setRecordingsLoading(false);
    }
  }, [session]);

  async function handleRecord(program: LiveTvProgram) {
    const programId = program.id?.trim();
    if (!programId || recordingInFlight.current) return;
    const stopMs = Date.parse(program.stop);
    if (Number.isFinite(stopMs) && stopMs <= Date.now()) {
      showRecordingMessage("error", "Program already ended");
      return;
    }
    recordingInFlight.current = true;
    setRecordingBusyId(programId);
    try {
      await scheduleLiveTvRecording(session, { program_id: programId });
      showRecordingMessage("success", "Recording scheduled");
      if (activeTab === "recordings") {
        await refreshRecordings();
      }
    } catch (err) {
      showRecordingMessage("error", scheduleRecordingErrorMessage(err));
    } finally {
      recordingInFlight.current = false;
      setRecordingBusyId(null);
    }
  }

  async function handleCancel(recording: LiveTvRecording) {
    const id = recording.id?.trim();
    if (!id || cancelInFlight.current) return;
    cancelInFlight.current = true;
    setCancelBusyId(id);
    try {
      await cancelLiveTvRecording(session, id);
      setRecordings((prev) => prev.filter((item) => item.id !== id));
      showRecordingMessage("success", "Recording cancelled");
    } catch (err) {
      showRecordingMessage("error", cancelRecordingErrorMessage(err));
    } finally {
      cancelInFlight.current = false;
      setCancelBusyId(null);
    }
  }

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const list = await fetchLiveTvChannels(session);
        if (cancelled) return;
        setChannels(list);
        if (list.length) {
          const guide = await fetchLiveTvGuide(
            session,
            list.map((ch) => ch.id),
          );
          if (!cancelled) setPrograms(guide);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof ApiError ? err.message : "Could not load Live TV");
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  useEffect(() => {
    if (activeTab !== "recordings") return;
    void refreshRecordings();
  }, [activeTab, refreshRecordings]);

  const channelById = useMemo(
    () => new Map(channels.map((channel) => [channel.id, channel])),
    [channels],
  );

  const scheduledRecordings = useMemo(
    () =>
      recordings.filter((recording) =>
        ["scheduled", "recording"].includes(recording.status.trim().toLowerCase()),
      ),
    [recordings],
  );

  const historyRecordings = useMemo(
    () =>
      recordings.filter(
        (recording) => !["scheduled", "recording"].includes(recording.status.trim().toLowerCase()),
      ),
    [recordings],
  );

  return (
    <section className="screen browse-screen livetv-screen">
      <header className="browse-header">
        <div>
          <p className="eyebrow">Broadcast</p>
          <h1 className="browse-title">Live TV</h1>
          <p className="muted">
            {loading
              ? "Loading channels…"
              : channels.length
                ? `${channels.length} channel${channels.length === 1 ? "" : "s"}`
                : "No enabled channels on this server"}
          </p>
        </div>
      </header>

      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}

      {recordingMessage ? (
        <p
          className={recordingMessage.kind === "error" ? "form-error" : "livetv-status-toast"}
          role={recordingMessage.kind === "error" ? "alert" : "status"}
        >
          {recordingMessage.text}
        </p>
      ) : null}

      {!loading && channels.length === 0 && !error ? (
        <p className="muted">
          An admin can add an HDHomeRun (or similar) tuner under Admin → Live TV on the Prairie
          server.
        </p>
      ) : null}

      {channels.length > 0 ? (
        <>
          <div
            className="season-tabs livetv-tabs"
            role="tablist"
            aria-label="Live TV sections"
            data-focus-container="horizontal"
            data-focus-count={3}
          >
            {(
              [
                ["guide", "Guide"],
                ["channels", "Channels"],
                ["recordings", "My recordings"],
              ] as const
            ).map(([tab, label], tabIndex) => (
              <button
                key={tab}
                type="button"
                role="tab"
                data-focus-index={tabIndex}
                aria-selected={activeTab === tab}
                className={`season-chip${activeTab === tab ? " is-active" : ""}`}
                autoFocus={tab === "guide"}
                onClick={() => setActiveTab(tab)}
              >
                {label}
                {tab === "recordings" && scheduledRecordings.length > 0 ? (
                  <span className="season-chip__count">{scheduledRecordings.length}</span>
                ) : null}
              </button>
            ))}
          </div>

          {activeTab === "guide" ? (
            <div className="livetv-guide" role="list" aria-label="Guide">
              {channels.map((channel, index) => {
                const now = currentProgramInIndex(guideIndex, channel.id);
                const next = nextProgramInIndex(guideIndex, channel.id);
                return (
                  <article
                    key={channel.id}
                    className="livetv-guide-row"
                    role="listitem"
                    tabIndex={-1}
                  >
                    <div className="livetv-guide-row__channel">
                      <span className="livetv-channel__num">
                        {channel.number_override || channel.number}
                        {channel.hd ? " HD" : ""}
                      </span>
                      <div className="livetv-channel__body">
                        <strong>{channelDisplayLabel(channel)}</strong>
                      </div>
                    </div>
                    <div className="livetv-guide-row__programs">
                      <div>
                        <p className="eyebrow">Now</p>
                        <p>{programLine(now, "Nothing listed")}</p>
                      </div>
                      <div>
                        <p className="eyebrow">Next</p>
                        <p>{programLine(next, "Nothing listed")}</p>
                      </div>
                    </div>
                    {/* One container per row: guide rows are ragged (Watch, plus
                        Record now / Record next only when listed), so the row is
                        the only shape the index model can describe. Up/Down then
                        steps row to row and clamps onto the nearest column. */}
                    <div
                      className="row-actions livetv-guide-row__actions"
                      data-focus-container="horizontal"
                      data-focus-count={1 + (now?.id ? 1 : 0) + (next?.id ? 1 : 0)}
                    >
                      <FocusButton
                        autoFocus={index === 0}
                        data-focus-index={0}
                        icon={<Play />}
                        onClick={() => onTune(channel)}
                      >
                        Watch
                      </FocusButton>
                      {now?.id ? (
                        <FocusButton
                          data-focus-index={1}
                          icon={<Circle />}
                          disabled={recordingBusyId !== null}
                          onClick={() => void handleRecord(now)}
                        >
                          {recordingBusyId === now.id ? "Scheduling…" : "Record now"}
                        </FocusButton>
                      ) : null}
                      {next?.id ? (
                        <FocusButton
                          data-focus-index={now?.id ? 2 : 1}
                          icon={<Circle />}
                          disabled={recordingBusyId !== null}
                          onClick={() => void handleRecord(next)}
                        >
                          {recordingBusyId === next.id ? "Scheduling…" : "Record next"}
                        </FocusButton>
                      ) : null}
                    </div>
                  </article>
                );
              })}
            </div>
          ) : null}

          {activeTab === "channels" ? (
            <div
              className="livetv-channel-list"
              role="list"
              aria-label="Channels"
              // Longest list in the app — without an indexed container every
              // D-pad press measured every focusable on the page.
              data-focus-container="vertical"
              data-focus-count={channels.length}
            >
              {channels.map((channel, index) => (
                <button
                  key={channel.id}
                  type="button"
                  role="listitem"
                  className="livetv-channel"
                  data-focus-index={index}
                  autoFocus={index === 0}
                  onClick={() => onTune(channel)}
                >
                  <span className="livetv-channel__num">
                    {channel.number_override || channel.number}
                    {channel.hd ? " HD" : ""}
                  </span>
                  <span className="livetv-channel__body">
                    <strong>{channelDisplayLabel(channel)}</strong>
                    <span className="muted">
                      {programLine(currentProgramInIndex(guideIndex, channel.id), "No guide data")}
                    </span>
                  </span>
                </button>
              ))}
            </div>
          ) : null}

          {activeTab === "recordings" ? (
            <div className="livetv-recordings">
              {recordingsLoading ? <p className="muted">Loading recordings…</p> : null}
              <RecordingsSection
                title="Scheduled & in progress"
                empty="Nothing scheduled yet. Pick a programme from the guide."
                recordings={scheduledRecordings}
                channelById={channelById}
                cancelBusyId={cancelBusyId}
                onCancel={(recording) => void handleCancel(recording)}
              />
              <RecordingsSection
                title="History"
                empty="Completed and failed recordings will show up here."
                recordings={historyRecordings}
                channelById={channelById}
                cancelBusyId={cancelBusyId}
                onCancel={(recording) => void handleCancel(recording)}
              />
            </div>
          ) : null}
        </>
      ) : null}
    </section>
  );
}

function RecordingsSection({
  title,
  empty,
  recordings,
  channelById,
  cancelBusyId,
  onCancel,
}: {
  title: string;
  empty: string;
  recordings: LiveTvRecording[];
  channelById: Map<string, LiveTvChannel>;
  cancelBusyId: string | null;
  onCancel: (recording: LiveTvRecording) => void;
}) {
  return (
    <section className="livetv-recordings-section">
      <h2 className="browse-title">{title}</h2>
      {recordings.length === 0 ? (
        <p className="muted">{empty}</p>
      ) : (
        <div className="livetv-recordings-list" role="list">
          {recordings.map((recording, index) => {
            const channel = channelById.get(recording.channel_id);
            const cancellable = canCancelRecording(recording);
            return (
              <article key={recording.id} className="livetv-recording-row" role="listitem">
                <div className="livetv-recording-row__body">
                  <strong>{recording.title?.trim() || "Untitled recording"}</strong>
                  <p className="muted">
                    {channel ? channelDisplayLabel(channel) : "Unknown channel"}
                    {" · "}
                    {formatRecordingWindow(recording)}
                  </p>
                  <p className="muted">{recordingStatusLabel(recording.status)}</p>
                </div>
                {cancellable ? (
                  <FocusButton
                    autoFocus={index === 0}
                    variant="ghost"
                    icon={<X />}
                    disabled={cancelBusyId !== null}
                    onClick={() => onCancel(recording)}
                  >
                    {cancelBusyId === recording.id ? "Cancelling…" : "Cancel"}
                  </FocusButton>
                ) : null}
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
