import { useEffect, useMemo, useRef, useState } from "react";
import {
  channelDisplayLabel,
  currentProgramForChannel,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  programProgressFraction,
  type LiveTvChannel,
  type LiveTvProgram,
} from "../api/livetv";
import { useFocusRescue } from "../focus/useFocusRescue";
import type { PrairieSession } from "../storage/session";
import { ArtworkImage } from "./ArtworkImage";
import { MediaRow } from "./MediaRow";

interface OnNowCard {
  channel: LiveTvChannel;
  title: string;
  stop: string;
  imageUrl: string;
  progress: number;
}

export type OnNowStatus = "loading" | "ready" | "empty";

interface LiveTvOnNowRowProps {
  session: PrairieSession;
  onOpenChannel: (channel: LiveTvChannel) => void;
  /** Lets Home reserve the slot and decide initial focus without a jump. */
  onStatusChange?: (status: OnNowStatus) => void;
}

function formatUntil(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
}

/** Same-height placeholder used while the Live TV probe or guide is unresolved. */
export function LiveTvOnNowSkeleton() {
  return (
    <MediaRow title="On now" variant="poster" className="media-row--on-now" skeleton>
      {Array.from({ length: 6 }).map((_, index) => (
        <div
          key={`on-now-skel-${index}`}
          className="poster-card poster-card--skeleton"
          aria-hidden="true"
        >
          <div className="poster-card__art" />
          <div className="poster-card__meta">
            <p className="poster-card__title">{"\u00a0"}</p>
            <p className="poster-card__subtitle is-empty">{"\u00a0"}</p>
          </div>
        </div>
      ))}
    </MediaRow>
  );
}

/**
 * Home-row teaser for currently airing Live TV programmes.
 * Hidden when the server has no enabled channels / guide slots.
 */
export function LiveTvOnNowRow({ session, onOpenChannel, onStatusChange }: LiveTvOnNowRowProps) {
  const [loading, setLoading] = useState(true);
  const [nowMs, setNowMs] = useState(() => Date.now());
  // The minute tick can drop the focused channel when its program ends; rescue
  // focus to a neighbouring card so the remote does not go dead.
  const rowRef = useRef<HTMLDivElement>(null);
  useFocusRescue(rowRef);

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 60_000);
    return () => window.clearInterval(id);
  }, []);

  /**
   * Fetch the line-up and the guide once per mount.
   *
   * The minute tick used to be a dependency of this effect, so every tick
   * re-requested both — on a screen that is usually also decoding artwork, and
   * for data that had not changed. The guide already covers a six-hour window,
   * so a minute later the answer to "what is on now" is in the response we
   * already hold; only the clock moved. Advancing the row is now pure
   * recomputation (see below), and the network is touched once.
   */
  const [channels, setChannels] = useState<LiveTvChannel[]>([]);
  const [programs, setPrograms] = useState<LiveTvProgram[]>([]);
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      try {
        const enabled = (await fetchLiveTvChannels(session)).filter((ch) => ch.enabled !== false);
        if (cancelled) return;
        const limited = enabled.slice(0, 24);
        setChannels(limited);
        if (!limited.length) {
          setPrograms([]);
          return;
        }
        const guide = await fetchLiveTvGuide(
          session,
          limited.map((ch) => ch.id),
        );
        if (!cancelled) setPrograms(guide);
      } catch {
        if (!cancelled) {
          setChannels([]);
          setPrograms([]);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  /** Which programme is airing, recomputed against the minute tick. */
  const cards = useMemo<OnNowCard[]>(() => {
    if (!channels.length || !programs.length) return [];
    return channels
      .map((channel) => {
        const program = currentProgramForChannel(programs, channel.id, nowMs);
        if (!program) return null;
        const poster = program.image_url?.trim() || "";
        const logo = channel.logo_url?.trim() || "";
        return {
          channel,
          title: program.title,
          stop: program.stop,
          imageUrl: poster || logo,
          progress: programProgressFraction(program.start, program.stop, nowMs),
        };
      })
      .filter((row): row is OnNowCard => row != null)
      .slice(0, 16);
  }, [channels, programs, nowMs]);

  const status: OnNowStatus = cards.length > 0 ? "ready" : loading ? "loading" : "empty";
  useEffect(() => {
    onStatusChange?.(status);
  }, [status, onStatusChange]);

  // First load only: hold a same-height slot so filling it in place cannot
  // reflow Home. The minute tick keeps the real cards mounted.
  if (loading && cards.length === 0) {
    return <LiveTvOnNowSkeleton />;
  }
  if (cards.length === 0) return null;

  return (
    <div ref={rowRef} style={{ display: "contents" }}>
      <MediaRow
        title="On now"
        variant="poster"
        className="media-row--on-now"
        items={cards}
        getItemKey={(item) => item.channel.id}
        renderItem={(item) => (
          <button
            type="button"
            className="poster-card on-now-card"
            onClick={() => onOpenChannel(item.channel)}
          >
            <div className="poster-card__art" aria-hidden="true">
              {item.imageUrl ? (
                <ArtworkImage
                  src={item.imageUrl}
                  alt=""
                  role="channel"
                  placeholderLabel={item.title}
                  loading="lazy"
                />
              ) : (
                <div className="poster-card__placeholder">{item.title.slice(0, 1) || "\u00a0"}</div>
              )}
              <span className="on-now-card__live">Live</span>
              {item.progress > 0.02 && item.progress < 0.98 ? (
                <div className="poster-card__progress">
                  <span style={{ width: `${Math.round(item.progress * 100)}%` }} />
                </div>
              ) : null}
            </div>
            <div className="poster-card__meta">
              <span className="poster-card__title">{item.title}</span>
              <span className="poster-card__subtitle">
                {channelDisplayLabel(item.channel)}
                {item.stop ? ` · until ${formatUntil(item.stop)}` : ""}
              </span>
            </div>
          </button>
        )}
      />
    </div>
  );
}
