import { ArrowLeft, Bookmark, CheckCircle2, Heart, Play, RotateCcw, Star } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { ApiError } from "../api/client";
import {
  fetchEpisodes,
  fetchItemDetail,
  fetchSeasons,
  type EpisodeSummary,
  type ItemDetail,
  type SeasonSummary,
} from "../api/catalog";
import { fetchSimilarItems } from "../api/recommendations";
import { setFavorite, setWatched, setWatchlist } from "../api/userState";
import { fetchWatchDetail, selectPlaybackFileId } from "../api/watch";
import { ArtworkImage } from "../components/ArtworkImage";
import { FocusButton } from "../components/FocusButton";
import { MediaRow } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import {
  crewLine,
  episodeProgressRatio,
  formatAirDate,
  formatResumeLabel,
  formatRuntimeMinutes,
  hasResumeProgress,
  isSeriesType,
  movieFacts,
  pickNextUpEpisode,
  resumePositionSeconds,
  seriesFacts,
  sourceTokens,
  starringText,
  type FactToken,
  typeLabel,
} from "../lib/detailMetadata";
import type { PlayerLaunch } from "./PlayerScreen";
import type { PrairieSession } from "../storage/session";

interface ItemDetailScreenProps {
  session: PrairieSession;
  contentId: string;
  onBack: () => void;
  onPlay: (launch: PlayerLaunch) => void;
  onOpenItem: (contentId: string) => void;
}

function episodeStill(episode: EpisodeSummary): string | null {
  const still = episode.still_url?.trim();
  if (still) return still;
  const poster = episode.poster_url?.trim();
  return poster || null;
}

function FactRow({ tokens }: { tokens: FactToken[] }) {
  if (!tokens.length) return null;
  return (
    <div className="detail-facts">
      {tokens.map((token, index) => {
        if (token.kind === "chip") {
          return (
            <span key={`${token.value}-${index}`} className="detail-chip">
              {token.value}
            </span>
          );
        }
        if (token.kind === "score") {
          return (
            <span key={`${token.value}-${index}`} className="detail-score">
              <Star size={14} fill="currentColor" />
              {token.value}
            </span>
          );
        }
        return (
          <span key={`${token.value}-${index}`} className="detail-fact">
            {index > 0 ? <span className="detail-fact__dot">·</span> : null}
            {token.value}
          </span>
        );
      })}
    </div>
  );
}

export function ItemDetailScreen({
  session,
  contentId,
  onBack,
  onPlay,
  onOpenItem,
}: ItemDetailScreenProps) {
  const [detail, setDetail] = useState<ItemDetail | null>(null);
  const [seasons, setSeasons] = useState<SeasonSummary[]>([]);
  const [seasonNumber, setSeasonNumber] = useState<number | null>(null);
  const [episodes, setEpisodes] = useState<EpisodeSummary[]>([]);
  const [episodesLoading, setEpisodesLoading] = useState(false);
  const [similar, setSimilar] = useState<ItemDetail[]>([]);
  const [loading, setLoading] = useState(true);
  const [busyPlay, setBusyPlay] = useState(false);
  const [busyAction, setBusyAction] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      setSeasons([]);
      setEpisodes([]);
      setSeasonNumber(null);
      setSimilar([]);
      try {
        const item = await fetchItemDetail(session, contentId);
        if (cancelled) return;
        setDetail(item);
        if (isSeriesType(item.type)) {
          const nextSeasons = await fetchSeasons(session, contentId);
          if (cancelled) return;
          setSeasons(nextSeasons);
          const first = nextSeasons[0]?.season_number ?? null;
          setSeasonNumber(first);
        }
        try {
          const refs = await fetchSimilarItems(session, contentId);
          const details = (
            await Promise.all(
              refs.slice(0, 12).map(async (ref) => {
                try {
                  return await fetchItemDetail(session, ref.media_item_id);
                } catch {
                  return null;
                }
              }),
            )
          ).filter((entry): entry is ItemDetail => entry != null);
          if (!cancelled) setSimilar(details);
        } catch {
          if (!cancelled) setSimilar([]);
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
    if (!isSeriesType(detail.type)) return;
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

  async function playContent(id: string, title: string, startFromBeginning = false) {
    setBusyPlay(true);
    setError(null);
    try {
      const watch = await fetchWatchDetail(session, id);
      const fileId = selectPlaybackFileId(watch);
      if (fileId == null) {
        throw new Error("No playable file for this title");
      }
      const startPositionSeconds = startFromBeginning
        ? undefined
        : resumePositionSeconds(
            watch.user_data?.position_seconds,
            watch.user_data?.duration_seconds,
          );
      onPlay({
        fileId,
        title: watch.title || title,
        contentId: id,
        startPositionSeconds,
        watch,
      });
    } catch (err) {
      setError(err instanceof ApiError || err instanceof Error ? err.message : "Play failed");
    } finally {
      setBusyPlay(false);
    }
  }

  async function toggleFavorite() {
    if (!detail) return;
    const next = !detail.user_state?.is_favorite;
    setBusyAction(true);
    setDetail({
      ...detail,
      user_state: {
        played: detail.user_state?.played ?? false,
        is_favorite: next,
        in_watchlist: detail.user_state?.in_watchlist ?? false,
      },
    });
    try {
      await setFavorite(session, contentId, next);
    } catch (err) {
      setDetail(detail);
      setError(err instanceof ApiError ? err.message : "Could not update favorite");
    } finally {
      setBusyAction(false);
    }
  }

  async function toggleWatchlist() {
    if (!detail) return;
    const next = !detail.user_state?.in_watchlist;
    setBusyAction(true);
    setDetail({
      ...detail,
      user_state: {
        played: detail.user_state?.played ?? false,
        is_favorite: detail.user_state?.is_favorite ?? false,
        in_watchlist: next,
      },
    });
    try {
      await setWatchlist(session, contentId, next);
    } catch (err) {
      setDetail(detail);
      setError(err instanceof ApiError ? err.message : "Could not update watchlist");
    } finally {
      setBusyAction(false);
    }
  }

  async function toggleWatched() {
    if (!detail) return;
    const next = !detail.user_state?.played;
    setBusyAction(true);
    setDetail({
      ...detail,
      user_state: {
        played: next,
        is_favorite: detail.user_state?.is_favorite ?? false,
        in_watchlist: detail.user_state?.in_watchlist ?? false,
      },
    });
    try {
      await setWatched(session, contentId, next);
    } catch (err) {
      setDetail(detail);
      setError(err instanceof ApiError ? err.message : "Could not update watched");
    } finally {
      setBusyAction(false);
    }
  }

  const isSeries = isSeriesType(detail?.type);
  const heroBackdropUrl = detail?.backdrop_url?.trim();
  const heroPosterUrl = detail?.poster_url?.trim();
  const heroLogoUrl = detail?.logo_url?.trim();
  const heroSrc = heroBackdropUrl || heroPosterUrl;
  const nextUp = useMemo(() => pickNextUpEpisode(episodes), [episodes]);
  const facts = detail
    ? isSeries
      ? seriesFacts(detail, seasons.length || detail.season_count)
      : movieFacts(detail)
    : [];
  const sources = detail ? sourceTokens(detail) : [];
  const starring = detail ? starringText(detail) : null;
  const directed = detail ? crewLine(detail) : null;
  const movieResume = hasResumeProgress(
    detail?.user_data?.position_seconds,
    detail?.user_data?.duration_seconds,
    detail?.user_data?.is_in_progress,
  );
  const movieResumeSeconds = resumePositionSeconds(
    detail?.user_data?.position_seconds,
    detail?.user_data?.duration_seconds,
  );
  const episodeResume = nextUp
    ? hasResumeProgress(
        nextUp.user_data?.position_seconds,
        nextUp.user_data?.duration_seconds,
        nextUp.user_data?.is_in_progress,
      )
    : false;

  const playLabel = (() => {
    if (busyPlay) return "Starting…";
    if (!isSeries) {
      if (movieResume && movieResumeSeconds != null) return formatResumeLabel(movieResumeSeconds);
      return "Play";
    }
    if (!nextUp) return "Play";
    const code =
      nextUp.season_number != null && nextUp.episode_number != null
        ? `S${nextUp.season_number} · E${nextUp.episode_number}`
        : null;
    if (episodeResume) return code ? `Resume ${code}` : "Resume";
    return code ? `Play ${code}` : "Play";
  })();

  const studios = detail?.studios?.filter(Boolean) ?? [];
  const networks = detail?.networks?.filter(Boolean) ?? [];
  const cast = detail?.cast ?? [];
  const extras = detail?.extras ?? [];

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
                <p className="eyebrow">{sources.join(" · ") || typeLabel(detail.type)}</p>
                {heroLogoUrl ? (
                  <div className="detail-hero__logo">
                    <ArtworkImage src={heroLogoUrl} alt={detail.title} />
                  </div>
                ) : (
                  <h1 className="browse-title">{detail.title}</h1>
                )}
                {detail.tagline ? <p className="detail-tagline">{detail.tagline}</p> : null}
                <div className="detail-meta-row">
                  {detail.content_rating ? (
                    <span className="detail-rating-chip">{detail.content_rating}</span>
                  ) : null}
                  <FactRow tokens={facts} />
                </div>
                {detail.rating_rt_critic != null || detail.rating_rt_audience != null ? (
                  <div className="detail-scores">
                    {detail.rating_rt_critic != null ? (
                      <span>Critics {detail.rating_rt_critic}%</span>
                    ) : null}
                    {detail.rating_rt_audience != null ? (
                      <span>Audience {detail.rating_rt_audience}%</span>
                    ) : null}
                  </div>
                ) : null}
                {detail.overview ? <p className="detail-overview">{detail.overview}</p> : null}
                {directed ? <p className="detail-crew muted">{directed}</p> : null}
                {starring ? <p className="detail-starring muted">{starring}</p> : null}

                <div className="row-actions detail-actions">
                  {!isSeries ? (
                    <FocusButton
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay}
                      onClick={() => void playContent(contentId, detail.title)}
                    >
                      {playLabel}
                    </FocusButton>
                  ) : nextUp ? (
                    <FocusButton
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay}
                      onClick={() => void playContent(nextUp.content_id, nextUp.title)}
                    >
                      {playLabel}
                    </FocusButton>
                  ) : null}
                  {(!isSeries && movieResume) || (isSeries && episodeResume && nextUp) ? (
                    <FocusButton
                      variant="secondary"
                      icon={<RotateCcw />}
                      disabled={busyPlay}
                      onClick={() =>
                        void playContent(
                          isSeries && nextUp ? nextUp.content_id : contentId,
                          isSeries && nextUp ? nextUp.title : detail.title,
                          true,
                        )
                      }
                    >
                      Start Over
                    </FocusButton>
                  ) : null}
                  <FocusButton
                    variant="circle"
                    active={Boolean(detail.user_state?.is_favorite)}
                    disabled={busyAction}
                    aria-label={
                      detail.user_state?.is_favorite ? "Remove from favorites" : "Add to favorites"
                    }
                    icon={<Heart fill={detail.user_state?.is_favorite ? "currentColor" : "none"} />}
                    onClick={() => void toggleFavorite()}
                  />
                  <FocusButton
                    variant="circle"
                    active={Boolean(detail.user_state?.in_watchlist)}
                    disabled={busyAction}
                    aria-label={
                      detail.user_state?.in_watchlist ? "Remove from watchlist" : "Add to watchlist"
                    }
                    icon={
                      <Bookmark fill={detail.user_state?.in_watchlist ? "currentColor" : "none"} />
                    }
                    onClick={() => void toggleWatchlist()}
                  />
                  <FocusButton
                    variant="circle"
                    active={Boolean(detail.user_state?.played)}
                    disabled={busyAction}
                    aria-label={detail.user_state?.played ? "Mark unwatched" : "Mark watched"}
                    icon={
                      <CheckCircle2 fill={detail.user_state?.played ? "currentColor" : "none"} />
                    }
                    onClick={() => void toggleWatched()}
                  />
                </div>
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
          <div className="detail-section-header">
            <div>
              <p className="eyebrow">
                {seasonNumber != null ? `Season ${seasonNumber}` : "Episodes"}
              </p>
              <h2 className="detail-section-title">Episodes</h2>
            </div>
            {seasons.find((s) => s.season_number === seasonNumber)?.episode_count != null ? (
              <p className="muted">
                {seasons.find((s) => s.season_number === seasonNumber)?.episode_count} episodes
              </p>
            ) : null}
          </div>
          {seasons.length > 1 ? (
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
                  {season.is_specials || season.season_number === 0
                    ? "Specials"
                    : season.title?.trim() || `Season ${season.season_number}`}
                  {season.episode_count != null ? (
                    <span className="season-chip__count">{season.episode_count}</span>
                  ) : null}
                </button>
              ))}
            </div>
          ) : null}

          {episodesLoading ? <p className="muted">Loading episodes…</p> : null}

          <div className="episode-grid">
            {!episodesLoading
              ? episodes.map((episode, index) => {
                  const still = episodeStill(episode);
                  const progress = episodeProgressRatio(episode);
                  const runtime = formatRuntimeMinutes(episode.runtime);
                  const airDate = formatAirDate(episode.air_date);
                  return (
                    <button
                      key={episode.content_id}
                      type="button"
                      className="episode-card"
                      autoFocus={index === 0 && !nextUp}
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
                        {episode.user_data?.played ? (
                          <span className="episode-card__watched">
                            <CheckCircle2 size={16} />
                          </span>
                        ) : null}
                        {progress != null ? (
                          <div className="poster-card__progress">
                            <span style={{ width: `${Math.round(progress * 100)}%` }} />
                          </div>
                        ) : null}
                      </div>
                      <span className="episode-card__body">
                        <strong>{episode.title}</strong>
                        <span className="muted episode-card__meta">
                          {[
                            episode.episode_number != null
                              ? `Episode ${episode.episode_number}`
                              : null,
                            runtime,
                            airDate,
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                        </span>
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

      {cast.length > 0 ? (
        <div className="detail-body-section">
          <div className="detail-section-header">
            <div>
              <p className="eyebrow">Cast</p>
              <h2 className="detail-section-title">& Crew</h2>
            </div>
          </div>
          <div className="cast-rail">
            {cast.slice(0, 16).map((member) => (
              <div
                key={`${member.person_id ?? member.name}-${member.character ?? ""}`}
                className="cast-card"
              >
                <div className="cast-card__photo" aria-hidden="true">
                  {member.photo_url ? (
                    <ArtworkImage src={member.photo_url} alt="" placeholderLabel={member.name} />
                  ) : (
                    <div className="cast-card__photo-empty">{member.name.slice(0, 1)}</div>
                  )}
                </div>
                <p className="cast-card__name">{member.name}</p>
                {member.character ? (
                  <p className="muted cast-card__role">{member.character}</p>
                ) : null}
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {extras.length > 0 ? (
        <div className="detail-body-section">
          <div className="detail-section-header">
            <div>
              <p className="eyebrow">Extras</p>
              <h2 className="detail-section-title">Bonus Content</h2>
            </div>
          </div>
          <div className="row-actions">
            {extras.map((extra) => (
              <FocusButton
                key={extra.content_id}
                variant="ghost"
                icon={<Play />}
                disabled={busyPlay}
                onClick={() => void playContent(extra.content_id, extra.title || "Extra")}
              >
                {extra.title || extra.kind}
              </FocusButton>
            ))}
          </div>
        </div>
      ) : null}

      {detail && (studios.length > 0 || networks.length > 0 || (detail.genres?.length ?? 0) > 0) ? (
        <div className="detail-body-section">
          <div className="detail-section-header">
            <div>
              <p className="eyebrow">Info</p>
              <h2 className="detail-section-title">Details</h2>
            </div>
          </div>
          <dl className="detail-facts-table">
            {detail.genres?.length ? (
              <>
                <dt>Genres</dt>
                <dd>{detail.genres.join(", ")}</dd>
              </>
            ) : null}
            {studios.length ? (
              <>
                <dt>Studios</dt>
                <dd>{studios.join(", ")}</dd>
              </>
            ) : null}
            {networks.length ? (
              <>
                <dt>Networks</dt>
                <dd>{networks.join(", ")}</dd>
              </>
            ) : null}
            {detail.release_date || detail.first_air_date ? (
              <>
                <dt>{isSeries ? "First Aired" : "Released"}</dt>
                <dd>{formatAirDate(detail.release_date || detail.first_air_date)}</dd>
              </>
            ) : null}
            {detail.show_status ? (
              <>
                <dt>Status</dt>
                <dd>{detail.show_status}</dd>
              </>
            ) : null}
          </dl>
        </div>
      ) : null}

      {similar.length > 0 ? (
        <div className="detail-body-section">
          <MediaRow title="More Like This">
            {similar.map((item) => (
              <PosterCard
                key={item.content_id}
                title={item.title}
                subtitle={item.year ? String(item.year) : item.type}
                posterUrl={item.poster_url}
                watched={Boolean(item.user_state?.played)}
                onSelect={() => onOpenItem(item.content_id)}
              />
            ))}
          </MediaRow>
        </div>
      ) : null}
    </section>
  );
}
