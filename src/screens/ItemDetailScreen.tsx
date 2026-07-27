import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import {
  fetchEpisodes,
  fetchItemDetail,
  fetchSeasons,
  type EpisodeSummary,
  type ItemDetail,
  type SeasonSummary,
} from "../api/catalog";
import { fetchWatchDetail, selectPlaybackFileId, type WatchDetail } from "../api/watch";
import { ArtworkImage } from "../components/ArtworkImage";
import { FocusButton } from "../components/FocusButton";
import type { PlayerLaunch } from "./PlayerScreen";
import type { PrairieSession } from "../storage/session";

interface ItemDetailScreenProps {
  session: PrairieSession;
  contentId: string;
  onBack: () => void;
  onPlay: (launch: PlayerLaunch) => void;
}

function resumeSeconds(watch: WatchDetail): number | undefined {
  const position = watch.user_data?.position_seconds;
  if (position == null || position <= 0) return undefined;
  const duration = watch.user_data?.duration_seconds;
  if (duration != null && duration > 0 && position / duration >= 0.95) return undefined;
  return position;
}

export function ItemDetailScreen({ session, contentId, onBack, onPlay }: ItemDetailScreenProps) {
  const [detail, setDetail] = useState<ItemDetail | null>(null);
  const [seasons, setSeasons] = useState<SeasonSummary[]>([]);
  const [seasonNumber, setSeasonNumber] = useState<number | null>(null);
  const [episodes, setEpisodes] = useState<EpisodeSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyPlay, setBusyPlay] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      setSeasons([]);
      setEpisodes([]);
      setSeasonNumber(null);
      try {
        const item = await fetchItemDetail(session, contentId);
        if (cancelled) return;
        setDetail(item);
        if (item.type === "series" || item.type === "show" || item.type === "tv") {
          const nextSeasons = await fetchSeasons(session, contentId);
          if (cancelled) return;
          setSeasons(nextSeasons);
          const first = nextSeasons[0]?.season_number ?? null;
          setSeasonNumber(first);
        }
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load title");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, contentId]);

  useEffect(() => {
    if (seasonNumber == null || !detail) return;
    if (!(detail.type === "series" || detail.type === "show" || detail.type === "tv")) return;
    let cancelled = false;
    void (async () => {
      try {
        const eps = await fetchEpisodes(session, contentId, seasonNumber);
        if (!cancelled) setEpisodes(eps);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof ApiError ? err.message : "Could not load episodes");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, contentId, seasonNumber, detail]);

  async function playContent(id: string, title: string) {
    setBusyPlay(true);
    setError(null);
    try {
      const watch = await fetchWatchDetail(session, id);
      const fileId = selectPlaybackFileId(watch);
      if (fileId == null) {
        throw new Error("No playable file for this title");
      }
      onPlay({
        fileId,
        title: watch.title || title,
        contentId: id,
        startPositionSeconds: resumeSeconds(watch),
        watch,
      });
    } catch (err) {
      setError(err instanceof ApiError || err instanceof Error ? err.message : "Play failed");
    } finally {
      setBusyPlay(false);
    }
  }

  const isSeries = detail?.type === "series" || detail?.type === "show" || detail?.type === "tv";

  return (
    <section className="screen detail-screen">
      <div className="detail-hero">
        {detail?.backdrop_url || detail?.poster_url ? (
          <ArtworkImage
            className="detail-hero__art"
            src={detail.backdrop_url || detail.poster_url || ""}
            alt=""
          />
        ) : (
          <div className="detail-hero__art detail-hero__art--empty" />
        )}
        <div className="detail-hero__shade" />
        <div className="detail-hero__content">
          <FocusButton variant="ghost" onClick={onBack}>
            Back
          </FocusButton>
          {loading ? <p className="muted">Loading…</p> : null}
          {detail ? (
            <>
              <p className="eyebrow">{detail.type}</p>
              <h1 className="browse-title">{detail.title}</h1>
              <p className="muted">{[detail.year, detail.type].filter(Boolean).join(" · ")}</p>
              {detail.overview ? <p className="detail-overview">{detail.overview}</p> : null}
              {!isSeries ? (
                <div className="row-actions">
                  <FocusButton
                    autoFocus
                    disabled={busyPlay}
                    onClick={() => void playContent(contentId, detail.title)}
                  >
                    {busyPlay ? "Starting…" : "Play"}
                  </FocusButton>
                </div>
              ) : null}
            </>
          ) : null}
          {error ? (
            <p className="form-error" role="alert">
              {error}
            </p>
          ) : null}
        </div>
      </div>

      {isSeries ? (
        <div className="detail-episodes">
          <div className="season-tabs">
            {seasons.map((season) => (
              <FocusButton
                key={season.season_number}
                variant={seasonNumber === season.season_number ? "primary" : "ghost"}
                onClick={() => setSeasonNumber(season.season_number)}
              >
                Season {season.season_number}
              </FocusButton>
            ))}
          </div>
          <div className="episode-list">
            {episodes.map((episode, index) => (
              <button
                key={episode.content_id}
                type="button"
                className="episode-row"
                autoFocus={index === 0}
                disabled={busyPlay}
                onClick={() => void playContent(episode.content_id, episode.title)}
              >
                <span className="episode-row__num">
                  {episode.episode_number != null ? `E${episode.episode_number}` : "Ep"}
                </span>
                <span className="episode-row__body">
                  <strong>{episode.title}</strong>
                  {episode.overview ? <span className="muted">{episode.overview}</span> : null}
                </span>
              </button>
            ))}
          </div>
          {seasons.length === 0 && !loading ? (
            <p className="muted">No seasons found for this series.</p>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
