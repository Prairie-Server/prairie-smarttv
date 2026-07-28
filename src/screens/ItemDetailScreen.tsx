import { ArrowLeft, Bookmark, CheckCircle2, Heart, Play, RotateCcw, Star } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "../api/client";
import {
  fetchEpisodes,
  fetchItemDetail,
  fetchSeasons,
  type CatalogItem,
  type EpisodeSummary,
  type ItemDetail,
  type SeasonSummary,
} from "../api/catalog";
import { fetchSimilarItems } from "../api/recommendations";
import { setFavorite, setWatched, setWatchlist } from "../api/userState";
import {
  fetchWatchDetail,
  selectPlaybackFileId,
  watchDetailFromItemDetail,
  type WatchDetail,
} from "../api/watch";
import { ArtworkImage } from "../components/ArtworkImage";
import { FocusButton } from "../components/FocusButton";
import { MediaRow } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import { useBackKey } from "../focus/useBackKey";
import { useStableItemSelect } from "../hooks/useStableItemSelect";
import {
  BACKDROP_HERO_WIDTH,
  LOGO_WIDTH,
  POSTER_WIDTH,
  PROFILE_WIDTH,
  STILL_WIDTH,
} from "../lib/artworkUrl";
import {
  crewLine,
  episodeProgressRatio,
  featuredCrew,
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

/** Cards per recommendations row, and how many item-detail calls run at once. */
const SIMILAR_LIMIT = 6;
const SIMILAR_FETCH_BATCH = 2;
/** Only fetch once the row is genuinely being approached. */
const SIMILAR_PREFETCH_MARGIN = "10% 0px";
/** And not before the hero's own requests and decodes have had a head start. */
const SIMILAR_HERO_GRACE_MS = 900;
/** Episode cards mounted initially; the rest expand on demand. */
const EPISODE_PAGE_SIZE = 8;

interface ItemDetailScreenProps {
  session: PrairieSession;
  contentId: string;
  onBack: () => void;
  onPlay: (launch: PlayerLaunch) => void;
  onOpenItem: (contentId: string) => void;
}

/** Artwork fields are strings by contract; tolerate anything else rather than throwing. */
function urlText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function episodeStill(episode: EpisodeSummary): string | null {
  const still = urlText(episode.still_url);
  if (still) return still;
  const poster = urlText(episode.poster_url);
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
  const [similar, setSimilar] = useState<CatalogItem[]>([]);
  const [similarLoading, setSimilarLoading] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busyPlay, setBusyPlay] = useState(false);
  const [busyAction, setBusyAction] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [episodeMountCount, setEpisodeMountCount] = useState(EPISODE_PAGE_SIZE);
  const playButtonRef = useRef<HTMLButtonElement | null>(null);
  const backButtonRef = useRef<HTMLButtonElement | null>(null);
  const watchCacheRef = useRef<Map<string, WatchDetail>>(new Map());

  const [similarNear, setSimilarNear] = useState(false);
  const [heroSettled, setHeroSettled] = useState(false);
  const similarObserverRef = useRef<IntersectionObserver | null>(null);
  const similarSlotRef = useCallback((node: HTMLElement | null) => {
    if (!node) return;
    if (typeof IntersectionObserver === "undefined") {
      // No observer: fall back to fetching after the hero grace period.
      setSimilarNear(true);
      return;
    }
    similarObserverRef.current?.disconnect();
    similarObserverRef.current = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setSimilarNear(true);
          similarObserverRef.current?.disconnect();
        }
      },
      { rootMargin: SIMILAR_PREFETCH_MARGIN },
    );
    similarObserverRef.current.observe(node);
  }, []);
  useEffect(() => {
    return () => similarObserverRef.current?.disconnect();
  }, []);

  useEffect(() => {
    if (!detail) return;
    const handle = window.setTimeout(() => setHeroSettled(true), SIMILAR_HERO_GRACE_MS);
    return () => window.clearTimeout(handle);
  }, [detail]);

  const similarWanted = similarNear && heroSettled;

  const selectSimilar = useStableItemSelect(onOpenItem);
  const similarItemKey = useCallback((item: CatalogItem) => item.content_id, []);
  const renderSimilarItem = useCallback(
    (item: CatalogItem) => (
      <PosterCard
        title={item.title}
        subtitle={item.year ? String(item.year) : item.type}
        posterUrl={item.poster_url}
        posterAvifUrl={item.poster_avif_url}
        watched={Boolean(item.user_state?.played)}
        onSelect={selectSimilar(item.content_id)}
      />
    ),
    [selectSimilar],
  );

  const handleBack = useCallback(() => {
    onBack();
  }, [onBack]);
  useBackKey(handleBack);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      setSeasons([]);
      setEpisodes([]);
      setSeasonNumber(null);
      setSimilar([]);
      setSimilarNear(false);
      setHeroSettled(false);
      setEpisodeMountCount(EPISODE_PAGE_SIZE);
      watchCacheRef.current.clear();
      try {
        const item = await fetchItemDetail(session, contentId);
        if (cancelled) return;
        setDetail(item);
        const fromDetail = watchDetailFromItemDetail(item);
        if (fromDetail) watchCacheRef.current.set(item.content_id, fromDetail);
        // Unblock the hero as soon as primary detail is ready — seasons and
        // recommendations must never gate Play / OK focus.
        setLoading(false);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load title");
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, contentId]);

  useEffect(() => {
    if (!detail || !isSeriesType(detail.type)) return;
    let cancelled = false;
    void (async () => {
      try {
        const nextSeasons = await fetchSeasons(session, contentId);
        if (cancelled) return;
        setSeasons(nextSeasons);
        const first = nextSeasons[0]?.season_number ?? null;
        setSeasonNumber(first);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof ApiError ? err.message : "Could not load seasons");
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, contentId, detail]);

  // Recommendations only return ids, so each card costs a full item-detail
  // request. Opening a title used to fan out 12 of them (plus 12 poster decodes)
  // before the viewer had scrolled anywhere near the row, which dominated the
  // time to a usable detail page. Wait until the row is approached, then fetch a
  // capped set in small batches so the connection pool stays free.
  useEffect(() => {
    if (!detail || !similarWanted) return;
    let cancelled = false;
    void (async () => {
      setSimilarLoading(true);
      try {
        const { refs, cards } = await fetchSimilarItems(session, contentId);
        if (cancelled) return;
        if (cards.length > 0) {
          // Server hydrated the row: no per-card lookup needed.
          setSimilar(cards.slice(0, SIMILAR_LIMIT));
          return;
        }
        // Older server: fall back to one item-detail request per card.
        const wanted = refs.slice(0, SIMILAR_LIMIT);
        const details: CatalogItem[] = [];
        for (let index = 0; index < wanted.length; index += SIMILAR_FETCH_BATCH) {
          if (cancelled) return;
          const batch = await Promise.all(
            wanted.slice(index, index + SIMILAR_FETCH_BATCH).map(async (ref) => {
              try {
                return await fetchItemDetail(session, ref.media_item_id);
              } catch {
                return null;
              }
            }),
          );
          for (const entry of batch) {
            if (entry) details.push(entry);
          }
          if (!cancelled) setSimilar([...details]);
        }
      } catch {
        if (!cancelled) setSimilar([]);
      } finally {
        if (!cancelled) setSimilarLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, contentId, detail, similarWanted]);

  useEffect(() => {
    if (seasonNumber == null || !detail) return;
    if (!isSeriesType(detail.type)) return;
    let cancelled = false;
    setEpisodeMountCount(EPISODE_PAGE_SIZE);
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

  // Prefetch watch metadata for the primary Play target so OK→player is local.
  useEffect(() => {
    if (!detail || isSeriesType(detail.type)) return;
    if (watchCacheRef.current.has(detail.content_id)) return;
    let cancelled = false;
    void (async () => {
      try {
        const watch = await fetchWatchDetail(session, detail.content_id);
        if (!cancelled) watchCacheRef.current.set(detail.content_id, watch);
      } catch {
        // Play will retry.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, detail]);

  const nextUp = useMemo(() => pickNextUpEpisode(episodes), [episodes]);

  // Prefetch watch for the series Play target once next-up is known.
  useEffect(() => {
    if (!nextUp) return;
    if (watchCacheRef.current.has(nextUp.content_id)) return;
    let cancelled = false;
    void (async () => {
      try {
        const watch = await fetchWatchDetail(session, nextUp.content_id);
        if (!cancelled) watchCacheRef.current.set(nextUp.content_id, watch);
      } catch {
        // Play will retry.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, nextUp]);

  // Back is the only control that exists before detail arrives, so park focus
  // there while loading — a bare OK press must never land on <body>.
  useEffect(() => {
    if (detail) return;
    const node = backButtonRef.current;
    if (!node) return;
    const active = document.activeElement;
    const alreadyFocused =
      active instanceof HTMLElement && active !== document.body && document.body.contains(active);
    if (alreadyFocused) return;
    node.focus({ preventScroll: true });
  }, [detail]);

  // Defensive: ensure Play receives focus once the hero is ready so OK cannot
  // land on <body> before autoFocus paints. Re-run when series Play enables.
  useEffect(() => {
    if (!detail || loading) return;
    const node = playButtonRef.current;
    if (!node || node.disabled) return;
    if (document.activeElement === node) return;
    const active = document.activeElement;
    // Keep the user's place if they already moved focus (including Back).
    if (active instanceof HTMLElement && active !== document.body && active.tabIndex >= 0) {
      // Still steal focus from Back once series Play becomes ready — that is
      // the intended entry control, and Back was only a parking spot.
      if (active !== backButtonRef.current) return;
    }
    node.focus({ preventScroll: true });
  }, [detail, loading, nextUp]);

  async function resolveWatchDetail(id: string): Promise<WatchDetail> {
    const cached = watchCacheRef.current.get(id);
    if (cached) return cached;
    if (detail && detail.content_id === id) {
      const fromDetail = watchDetailFromItemDetail(detail);
      if (fromDetail) {
        watchCacheRef.current.set(id, fromDetail);
        return fromDetail;
      }
    }
    const watch = await fetchWatchDetail(session, id);
    watchCacheRef.current.set(id, watch);
    return watch;
  }

  async function playContent(id: string, title: string, startFromBeginning = false) {
    setBusyPlay(true);
    setError(null);
    try {
      const watch = await resolveWatchDetail(id);
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
  const heroBackdropUrl = urlText(detail?.backdrop_url);
  const heroPosterUrl = urlText(detail?.poster_url);
  const heroLogoUrl = urlText(detail?.logo_url);
  const heroBackdropAvif = urlText(detail?.backdrop_avif_url) || null;
  const heroPosterAvif = urlText(detail?.poster_avif_url) || null;
  const heroSrc = heroBackdropUrl || heroPosterUrl;
  const heroAvif = heroBackdropUrl ? heroBackdropAvif : heroPosterAvif;
  const visibleEpisodes = useMemo(
    () => episodes.slice(0, episodeMountCount),
    [episodes, episodeMountCount],
  );
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
  const crew = detail ? featuredCrew(detail) : [];
  const extras = detail?.extras ?? [];
  const seriesPlayReady = Boolean(nextUp);

  return (
    <section className="screen detail-screen">
      <div className="detail-hero">
        {heroSrc ? (
          <ArtworkImage
            className="detail-hero__art"
            src={heroSrc}
            avifSrc={heroAvif}
            alt=""
            widthHint={heroBackdropUrl ? BACKDROP_HERO_WIDTH : POSTER_WIDTH}
            loading="eager"
            decoding="async"
          />
        ) : (
          <div className="detail-hero__art detail-hero__art--empty" />
        )}
        <div className="detail-hero__shade" />
        <div className="detail-hero__content">
          <button
            ref={backButtonRef}
            type="button"
            className="detail-back"
            onClick={handleBack}
            aria-label="Back"
            autoFocus={!detail}
          >
            <ArrowLeft size={22} aria-hidden="true" />
            <span>Back</span>
          </button>
          {loading ? <p className="muted">Loading…</p> : null}
          {detail ? (
            <div className="detail-hero__body">
              {heroPosterUrl && heroBackdropUrl ? (
                <div className="detail-hero__poster" aria-hidden="true">
                  <ArtworkImage
                    src={heroPosterUrl}
                    avifSrc={heroPosterAvif}
                    alt=""
                    placeholderLabel={detail.title}
                    widthHint={POSTER_WIDTH}
                    width={220}
                    height={330}
                    loading="eager"
                    decoding="async"
                  />
                </div>
              ) : null}
              <div className="detail-hero__copy">
                <p className="eyebrow">{sources.join(" · ") || typeLabel(detail.type)}</p>
                {heroLogoUrl ? (
                  <div className="detail-hero__logo">
                    <ArtworkImage
                      src={heroLogoUrl}
                      alt={detail.title}
                      widthHint={LOGO_WIDTH}
                      width={352}
                      height={120}
                      loading="eager"
                      decoding="async"
                    />
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
                      ref={playButtonRef}
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay}
                      onClick={() => void playContent(contentId, detail.title)}
                    >
                      {playLabel}
                    </FocusButton>
                  ) : (
                    <FocusButton
                      ref={playButtonRef}
                      autoFocus
                      icon={<Play />}
                      disabled={busyPlay || !seriesPlayReady}
                      onClick={() => {
                        if (!nextUp) return;
                        void playContent(nextUp.content_id, nextUp.title);
                      }}
                    >
                      {playLabel}
                    </FocusButton>
                  )}
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
              ? visibleEpisodes.map((episode, index) => {
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
                            widthHint={STILL_WIDTH}
                            width={280}
                            height={158}
                            loading="lazy"
                            decoding="async"
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
                            <span
                              style={{
                                width: `${Math.round(progress * 100)}%`,
                              }}
                            />
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
          {!episodesLoading && episodes.length > episodeMountCount ? (
            <div className="row-actions" style={{ marginTop: "0.75rem" }}>
              <FocusButton
                variant="ghost"
                onClick={() =>
                  setEpisodeMountCount((count) =>
                    Math.min(episodes.length, count + EPISODE_PAGE_SIZE),
                  )
                }
              >
                More episodes ({episodes.length - episodeMountCount} left)
              </FocusButton>
            </div>
          ) : null}

          {seasons.length === 0 && !loading ? (
            <p className="muted">No seasons found for this series.</p>
          ) : null}
          {!episodesLoading && seasons.length > 0 && episodes.length === 0 ? (
            <p className="muted">No episodes are available for this season yet.</p>
          ) : null}
        </div>
      ) : null}

      {/* Cast/crew photos compete with the hero for the decode queue — wait. */}
      {heroSettled && (cast.length > 0 || crew.length > 0) ? (
        <div className="detail-body-section">
          {cast.length > 0 ? (
            <>
              <div className="detail-section-header">
                <div>
                  <p className="eyebrow">People</p>
                  <h2 className="detail-section-title">Cast</h2>
                </div>
              </div>
              <div className="cast-rail">
                {cast.slice(0, 12).map((member, index) => (
                  <div
                    key={`${member.person_id ?? member.name ?? index}-${member.character ?? ""}`}
                    className="cast-card"
                  >
                    <div className="cast-card__photo" aria-hidden="true">
                      {member.photo_url ? (
                        <ArtworkImage
                          src={member.photo_url}
                          alt=""
                          placeholderLabel={member.name}
                          widthHint={PROFILE_WIDTH}
                          width={120}
                          height={120}
                          loading="lazy"
                        />
                      ) : (
                        <div className="cast-card__photo-empty">
                          {(member.name ?? "?").slice(0, 1)}
                        </div>
                      )}
                    </div>
                    <p className="cast-card__name">{member.name}</p>
                    {member.character ? (
                      <p className="muted cast-card__role">{member.character}</p>
                    ) : null}
                  </div>
                ))}
              </div>
            </>
          ) : null}

          {crew.length > 0 ? (
            <>
              <div
                className={`detail-section-header${cast.length > 0 ? " detail-section-header--follow" : ""}`}
              >
                <div>
                  {cast.length === 0 ? <p className="eyebrow">People</p> : null}
                  <h2 className="detail-section-title">Crew</h2>
                </div>
              </div>
              <div className="cast-rail">
                {crew.map((member, index) => (
                  <div
                    key={`${member.person_id ?? member.name ?? index}-${member.job ?? ""}`}
                    className="cast-card"
                  >
                    <div className="cast-card__photo" aria-hidden="true">
                      {member.photo_url ? (
                        <ArtworkImage
                          src={member.photo_url}
                          alt=""
                          placeholderLabel={member.name}
                          widthHint={PROFILE_WIDTH}
                          width={120}
                          height={120}
                          loading="lazy"
                        />
                      ) : (
                        <div className="cast-card__photo-empty">
                          {(member.name ?? "?").slice(0, 1)}
                        </div>
                      )}
                    </div>
                    <p className="cast-card__name">{member.name}</p>
                    {member.job ? <p className="muted cast-card__role">{member.job}</p> : null}
                  </div>
                ))}
              </div>
            </>
          ) : null}
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
          <MediaRow
            title="More Like This"
            items={similar}
            getItemKey={similarItemKey}
            renderItem={renderSimilarItem}
          />
        </div>
      ) : detail ? (
        <div className="detail-body-section" ref={similarSlotRef}>
          <p className="eyebrow">More Like This</p>
          <p className="muted">{similarLoading ? "Loading…" : ""}</p>
        </div>
      ) : null}
    </section>
  );
}
