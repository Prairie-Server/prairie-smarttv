import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiError } from "../api/client";
import { fetchHomeSections, type HomeSection } from "../api/home";
import type { LiveTvChannel } from "../api/livetv";
import { HomeHero } from "../components/HomeHero";
import { LandscapeCard } from "../components/LandscapeCard";
import { LiveTvOnNowRow, type OnNowStatus } from "../components/LiveTvOnNowRow";
import { MediaRow, mediaRowMinHeight, type MediaRowVariant } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import { catalogItemProgress, catalogItemSubtitle, usesLandscapeCards } from "../lib/browseCards";
import { formatRuntimeSeconds } from "../lib/detailMetadata";
import type { PrairieSession } from "../storage/session";

interface HomeBrowseScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
  onOpenLiveChannel?: (channel: LiveTvChannel) => void;
  showOnNow?: boolean;
}

const SKELETON_ROW_COUNT = 4;
const SKELETON_CARD_COUNT = 8;
/** Rows mounted in the first commit; the rest follow one frame at a time. */
const INITIAL_ROW_COUNT = 2;
const ROW_MOUNT_CHUNK = 2;
/** How long entry focus waits for On now before settling on the first row. */
const ON_NOW_FOCUS_GRACE_MS = 700;

export function HomeBrowseScreen({
  session,
  onOpenItem,
  onOpenLiveChannel,
  showOnNow = false,
}: HomeBrowseScreenProps) {
  const [sections, setSections] = useState<HomeSection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [heroIndex, setHeroIndex] = useState(0);
  const [mountedRowCount, setMountedRowCount] = useState(INITIAL_ROW_COUNT);
  const [onNowStatus, setOnNowStatus] = useState<OnNowStatus>("loading");
  const paneRef = useRef<HTMLElement>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const next = await fetchHomeSections(session);
        if (!cancelled) {
          setSections(next.filter((s) => s.items.length > 0));
          setHeroIndex(0);
          setMountedRowCount(INITIAL_ROW_COUNT);
        }
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load home");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  const featured = useMemo(() => sections.find((section) => section.featured) ?? null, [sections]);
  const rows = useMemo(
    () => sections.filter((section) => section !== featured),
    [sections, featured],
  );

  const expectOnNow = showOnNow && onOpenLiveChannel != null;
  const handleOnNowStatus = useCallback((status: OnNowStatus) => setOnNowStatus(status), []);

  // Reserve the height a real row actually occupies rather than the design
  // min-height, so deferred rows do not grow the page as they mount. Measured
  // from the rows that are already up; falls back to the design value.
  const [rowHeights, setRowHeights] = useState<Partial<Record<MediaRowVariant, number>>>({});
  useEffect(() => {
    if (loading) return;
    const pane = paneRef.current;
    if (!pane) return;
    setRowHeights((prev) => {
      let next = prev;
      for (const variant of ["poster", "landscape"] as const) {
        const row = pane.querySelector<HTMLElement>(
          `.media-row--${variant}:not(.media-row--deferred):not(.media-row--skeleton)`,
        );
        const height = Math.round(row?.getBoundingClientRect().height ?? 0);
        if (height > 0 && prev[variant] !== height) {
          next = { ...next, [variant]: height };
        }
      }
      return next;
    });
  }, [loading, mountedRowCount, rows.length]);

  const reservedHeight = (variant: MediaRowVariant): string | number =>
    rowHeights[variant] ?? mediaRowMinHeight(variant);

  // Mount below-the-fold rows a chunk per frame: first paint only pays for the
  // rows in view, and the reserved-height placeholders keep the page stable.
  useEffect(() => {
    if (loading || mountedRowCount >= rows.length) return;
    const handle = window.requestAnimationFrame(() => {
      setMountedRowCount((count) => Math.min(rows.length, count + ROW_MOUNT_CHUNK));
    });
    return () => window.cancelAnimationFrame(handle);
  }, [loading, mountedRowCount, rows.length]);

  // Entry focus goes to the topmost real card in DOM order — On now when it has
  // cards, otherwise the first row — instead of a hardcoded row index. Waiting
  // for On now to resolve avoids focusing a row and then jumping up to it, but
  // the wait is bounded so a slow guide never leaves the screen unfocused.
  const [onNowGraceExpired, setOnNowGraceExpired] = useState(false);
  useEffect(() => {
    if (!expectOnNow) return;
    const handle = window.setTimeout(() => setOnNowGraceExpired(true), ON_NOW_FOCUS_GRACE_MS);
    return () => window.clearTimeout(handle);
  }, [expectOnNow]);
  const awaitingOnNow = expectOnNow && onNowStatus === "loading" && !onNowGraceExpired;
  useEffect(() => {
    if (loading || error || featured || awaitingOnNow) return;
    const pane = paneRef.current;
    if (!pane) return;
    const active = document.activeElement;
    if (active instanceof HTMLElement && active !== document.body && pane.contains(active)) return;
    const first = pane.querySelector<HTMLElement>(
      'button:not([disabled]), [tabindex]:not([tabindex="-1"])',
    );
    first?.focus({ preventScroll: true });
  }, [loading, error, featured, awaitingOnNow, rows.length, onNowStatus, mountedRowCount]);

  return (
    <section className="browse-pane browse-pane--home" ref={paneRef}>
      {loading ? (
        <>
          <div className="home-hero home-hero--skeleton" aria-hidden="true" />
          {Array.from({ length: SKELETON_ROW_COUNT }).map((_, rowIndex) => (
            <MediaRow key={`home-skel-${rowIndex}`} title="" skeleton>
              {Array.from({ length: SKELETON_CARD_COUNT }).map((__, cardIndex) => (
                <PosterCard
                  key={`home-skel-${rowIndex}-${cardIndex}`}
                  title=""
                  subtitle={null}
                  posterUrl={null}
                  disabled
                  onSelect={() => {
                    // Disabled skeleton; no-op.
                  }}
                />
              ))}
            </MediaRow>
          ))}
        </>
      ) : null}

      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}

      {!loading && !error && sections.length === 0 ? (
        <div className="browse-empty">
          <h1 className="browse-title">Home</h1>
          <p className="muted">No home rows yet — browse Libraries to find something to play.</p>
        </div>
      ) : null}

      {!loading && featured ? (
        <HomeHero
          items={featured.items}
          index={heroIndex}
          onIndexChange={setHeroIndex}
          onOpenItem={onOpenItem}
        />
      ) : null}

      {!loading && expectOnNow && onOpenLiveChannel ? (
        <LiveTvOnNowRow
          session={session}
          onOpenChannel={onOpenLiveChannel}
          onStatusChange={handleOnNowStatus}
        />
      ) : null}

      {!loading
        ? rows.map((section, sectionIndex) => {
            const landscape = usesLandscapeCards(section.section_type, section.items);
            if (sectionIndex >= mountedRowCount) {
              const variant: MediaRowVariant = landscape ? "landscape" : "poster";
              return (
                <div
                  key={section.id || section.title}
                  className={`media-row media-row--${variant} media-row--deferred`}
                  style={{ minHeight: reservedHeight(variant) }}
                  aria-hidden="true"
                />
              );
            }
            return (
              <MediaRow
                key={section.id || section.title}
                title={section.title}
                variant={landscape ? "landscape" : "poster"}
                items={section.items}
                getItemKey={(item, itemIndex) => `${section.id}-${item.content_id}-${itemIndex}`}
                renderItem={(item, itemIndex) => {
                  const progress = catalogItemProgress(item);
                  if (landscape) {
                    const remaining =
                      item.duration_seconds != null && item.position_seconds != null
                        ? formatRuntimeSeconds(item.duration_seconds - item.position_seconds)
                        : null;
                    return (
                      <LandscapeCard
                        title={item.title}
                        subtitle={
                          item.series_title
                            ? `${item.series_title}${
                                item.season_number != null && item.episode_number != null
                                  ? ` · S${item.season_number}E${item.episode_number}`
                                  : ""
                              }`
                            : catalogItemSubtitle(item)
                        }
                        meta={remaining ? `${remaining} left` : null}
                        imageUrl={item.backdrop_url || item.poster_url}
                        progress={progress}
                        watched={Boolean(item.user_state?.played)}
                        imageLoading={sectionIndex === 0 && itemIndex < 2 ? "eager" : "lazy"}
                        onSelect={() => onOpenItem(item.content_id)}
                      />
                    );
                  }
                  return (
                    <PosterCard
                      title={item.title}
                      subtitle={catalogItemSubtitle(item)}
                      posterUrl={item.poster_url}
                      progress={progress}
                      watched={Boolean(item.user_state?.played)}
                      favorite={Boolean(item.user_state?.is_favorite)}
                      imageLoading={sectionIndex === 0 && itemIndex < 3 ? "eager" : "lazy"}
                      onSelect={() => onOpenItem(item.content_id)}
                    />
                  );
                }}
              />
            );
          })
        : null}
    </section>
  );
}
