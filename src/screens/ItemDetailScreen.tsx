import { ArrowLeft, Play } from "lucide-react";
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

function episodeStill(episode: EpisodeSummary): string | null {
  const still = episode.still_url?.trim();
  if (still) return still;
  const poster = episode.poster_url?.trim();
  return poster || null;
}

export function ItemDetailScreen({ session, contentId, onBack, onPlay }: ItemDetailScreenProps) {
  const [detail, setDetail] = useState<ItemDetail | null>(null);
  const [seasons, setSeasons] = useState<SeasonSummary[]>([]);
  const [seasonNumber, setSeasonNumber] = useState<number | null>(null);
  const [episodes, setEpisodes] = useState<EpisodeSummary[]>([]);
  const [episodesLoading, setEpisodesLoading] = useState(false);
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
      setEpisodesLoading(true);
      try {
        const eps = await fetchEpisodes(session, contentId, seasonNumber);
        if (!cancelled) setEpisodes(eps);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof ApiError ? err.message : "Could not load episodes");
        }
      } finally {
        if (!cancelled) setEpisodesLoading(false);
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
  const heroBackdropUrl = detail?.backdrop_url?.trim();
  const heroPosterUrl = detail?.poster_url?.trim();
  const heroSrc = heroBackdropUrl || heroPosterUrl;
  const firstEpisode = episodes[0];

  return (
    <section className="screen detail-screen">
      <div className="detail-hero">
        {heroSrc ? (
          <ArtworkImage className="detail-hero__art" src={heroSrc} alt="" />
        ) : (
          <div className="detail-hero__art detail-hero__art--empty" />
        )}
        <div className="detail-hero__shade" />
        <div className="detail-hero__content">
          <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={onBack}>
            Back
          </FocusButton>
          {loading ? <p className="muted">Loading…</p> : null}
          {detail ? (
            <div className="detail-hero__body">
              {heroPosterUrl && heroBackdropUrl ? (
                <div className="detail-hero__poster" aria-hidden="true">
                  <ArtworkImage src={heroPosterUrl} alt="" placeholderLabel={detail.title} />
                </div>
              ) : null}
              <div className="detail-hero__copy">
                <p className="eyebrow">{detail.type}</p>
                <h1 className="browse-title">{detail.title}</h1>
                <p className="muted">{[detail.year, detail.type].filter(Boolean).join(" · ")}</p>
                {detail.overview ? <p className="detail-overview">{detail.overview}</p> : null}
                {!isSeries ? (
                  <div className="row-actions">
                    <FocusButton
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay}
                      onClick={() => void playContent(contentId, detail.title)}
                    >
                      {busyPlay ? "Starting…" : "Play"}
                    </FocusButton>
                  </div>
                ) : firstEpisode ? (
                  <div className="row-actions">
                    <FocusButton
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay}
                      onClick={() => void playContent(firstEpisode.content_id, firstEpisode.title)}
                    >
                      {busyPlay
                        ? "Starting…"
                        : firstEpisode.episode_number != null
                          ? `Play S${seasonNumber}E${firstEpisode.episode_number}`
                          : "Play"}
                    </FocusButton>
                  </div>
                ) : null}
              </div>
            </div>
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
          <div className="season-tabs" role="tablist" aria-label="Seasons">
            {seasons.map((season) => (
              <button
                key={season.season_number}
                type="button"
                role="tab"
                aria-selected={seasonNumber === season.season_number}
                className={`season-chip${seasonNumber === season.season_number ? " is-active" : ""}`}
                onClick={() => setSeasonNumber(season.season_number)}
              >
                {season.title?.trim() || `Season ${season.season_number}`}
                {season.episode_count != null ? (
                  <span className="season-chip__count">{season.episode_count}</span>
                ) : null}
              </button>
            ))}
          </div>

          {episodesLoading ? <p className="muted">Loading episodes…</p> : null}

          <div className="episode-grid">
            {!episodesLoading
              ? episodes.map((episode, index) => {
                  const still = episodeStill(episode);
                  return (
                    <button
                      key={episode.content_id}
                      type="button"
                      className="episode-card"
                      autoFocus={index === 0 && !firstEpisode}
                      disabled={busyPlay}
                      onClick={() => void playContent(episode.content_id, episode.title)}
                    >
                      <div className="episode-card__still" aria-hidden="true">
                        {still ? (
                          <ArtworkImage
                            src={still}
                            alt=""
                            placeholderLabel={episode.title}
                            loading={index < 6 ? "eager" : "lazy"}
                          />
                        ) : (
                          <div className="episode-card__still-empty">
                            <Play size={28} />
                          </div>
                        )}
                        <span className="episode-card__badge">
                          {episode.episode_number != null ? `E${episode.episode_number}` : "Ep"}
                        </span>
                      </div>
                      <span className="episode-card__body">
                        <strong>{episode.title}</strong>
                        {episode.overview ? (
                          <span className="muted episode-card__overview">{episode.overview}</span>
                        ) : null}
                      </span>
                    </button>
                  );
                })
              : null}
          </div>

          {seasons.length === 0 && !loading ? (
            <p className="muted">No seasons found for this series.</p>
          ) : null}
          {!episodesLoading && seasons.length > 0 && episodes.length === 0 ? (
            <p className="muted">No episodes are available for this season yet.</p>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
