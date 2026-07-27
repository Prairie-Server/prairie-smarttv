import { useEffect, useState } from "react";
import type { LiveTvChannel } from "../api/livetv";
import {
  channelDisplayLabel,
  currentProgramForChannel,
  fetchLiveTvChannels,
  fetchLiveTvGuide,
  programProgressFraction,
} from "../api/livetv";
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

/**
 * Home-row teaser for currently airing Live TV programmes.
 * Hidden when the server has no enabled channels / guide slots.
 */
export function LiveTvOnNowRow({ session, onOpenChannel, onStatusChange }: LiveTvOnNowRowProps) {
  const [loading, setLoading] = useState(true);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const [cards, setCards] = useState<OnNowCard[]>([]);

  const status: OnNowStatus = cards.length > 0 ? "ready" : loading ? "loading" : "empty";
  useEffect(() => {
    onStatusChange?.(status);
  }, [status, onStatusChange]);

  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 60_000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      try {
        const enabled = (await fetchLiveTvChannels(session)).filter((ch) => ch.enabled !== false);
        if (cancelled) return;
        const limited = enabled.slice(0, 24);
        if (!limited.length) {
          setCards([]);
          return;
        }
        const programs = await fetchLiveTvGuide(
          session,
          limited.map((ch) => ch.id),
        );
        if (cancelled) return;
        const now = Date.now();
        const nextCards = limited
          .map((channel) => {
            const program = currentProgramForChannel(programs, channel.id, now);
            if (!program) return null;
            const poster = program.image_url?.trim() || "";
            const logo = channel.logo_url?.trim() || "";
            return {
              channel,
              title: program.title,
              stop: program.stop,
              imageUrl: poster || logo,
              progress: programProgressFraction(program.start, program.stop, now),
            };
          })
          .filter((row): row is OnNowCard => row != null)
          .slice(0, 16);
        setCards(nextCards);
      } catch {
        if (!cancelled) setCards([]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, nowMs]);

  // First load only: hold a same-height slot so filling it in place cannot
  // reflow Home. The 60s guide refresh keeps the real cards mounted.
  if (loading && cards.length === 0) {
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
  if (cards.length === 0) return null;

  return (
    <MediaRow
      title="On now"
      variant="poster"
      className="media-row--on-now"
      items={cards}
      getItemKey={(item) => item.channel.id}
      renderItem={(item, index) => (
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
                placeholderLabel={item.title}
                loading={index < 4 ? "eager" : "lazy"}
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
  );
}
