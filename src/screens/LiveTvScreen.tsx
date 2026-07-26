import { useEffect, useMemo, useState } from "react";
import { ApiError } from "../api/client";
import {
  channelDisplayLabel,
  currentProgramForChannel,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  nextProgramForChannel,
  type LiveTvChannel,
  type LiveTvProgram,
} from "../api/livetv";
import { FocusButton } from "../components/FocusButton";
import type { PrairieSession } from "../storage/session";

interface LiveTvScreenProps {
  session: PrairieSession;
  onTune: (channel: LiveTvChannel) => void;
}

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

export function LiveTvScreen({ session, onTune }: LiveTvScreenProps) {
  const [channels, setChannels] = useState<LiveTvChannel[]>([]);
  const [programs, setPrograms] = useState<LiveTvProgram[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const list = await fetchLiveTvChannels(session);
        if (cancelled) return;
        setChannels(list);
        if (list[0]) setSelectedId(list[0].id);
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

  const selected = useMemo(
    () => channels.find((ch) => ch.id === selectedId) ?? channels[0] ?? null,
    [channels, selectedId],
  );

  const now = selected ? currentProgramForChannel(programs, selected.id) : null;
  const next = selected ? nextProgramForChannel(programs, selected.id) : null;

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

      {!loading && channels.length === 0 && !error ? (
        <p className="muted">
          An admin can add an HDHomeRun (or similar) tuner under Admin → Live TV on the Prairie
          server.
        </p>
      ) : null}

      {channels.length > 0 ? (
        <div className="livetv-layout">
          <div className="livetv-channel-list" role="list">
            {channels.map((channel, index) => (
              <button
                key={channel.id}
                type="button"
                role="listitem"
                className={
                  selected?.id === channel.id ? "livetv-channel is-selected" : "livetv-channel"
                }
                autoFocus={index === 0}
                onClick={() => setSelectedId(channel.id)}
                onDoubleClick={() => onTune(channel)}
              >
                <span className="livetv-channel__num">
                  {channel.number_override || channel.number}
                  {channel.hd ? " HD" : ""}
                </span>
                <span className="livetv-channel__body">
                  <strong>{channelDisplayLabel(channel)}</strong>
                  <span className="muted">
                    {programLine(currentProgramForChannel(programs, channel.id), "No guide data")}
                  </span>
                </span>
              </button>
            ))}
          </div>

          {selected ? (
            <aside className="livetv-detail">
              <p className="eyebrow">Selected</p>
              <h2 className="browse-title">{channelDisplayLabel(selected)}</h2>
              <p className="muted">
                Channel {selected.number_override || selected.number}
                {selected.hd ? " · HD" : ""}
              </p>
              <div className="livetv-now-next">
                <div>
                  <p className="eyebrow">Now</p>
                  <p>{programLine(now, "Nothing listed")}</p>
                  {now?.description ? <p className="muted">{now.description}</p> : null}
                </div>
                <div>
                  <p className="eyebrow">Next</p>
                  <p>{programLine(next, "Nothing listed")}</p>
                </div>
              </div>
              <div className="row-actions">
                <FocusButton autoFocus={false} onClick={() => onTune(selected)}>
                  Watch
                </FocusButton>
              </div>
            </aside>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
