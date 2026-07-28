import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { CatalogItem } from "../api/catalog";
import { ApiError } from "../api/client";
import { fetchHomeSections, type HomeSection } from "../api/home";
import type { LiveTvChannel } from "../api/livetv";
import { HomeHero } from "../components/HomeHero";
import { LandscapeCard } from "../components/LandscapeCard";
import {
  LiveTvOnNowRow,
  LiveTvOnNowSkeleton,
  type OnNowStatus,
} from "../components/LiveTvOnNowRow";
import { MediaRow, mediaRowMinHeight, type MediaRowVariant } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import { catalogItemProgress, catalogItemSubtitle, usesLandscapeCards } from "../lib/browseCards";
import { loadCachedHomeSections, saveCachedHomeSections } from "../lib/homeSectionsCache";
import { formatRuntimeSeconds } from "../lib/detailMetadata";
import { useStableItemSelect } from "../hooks/useStableItemSelect";
import type { PrairieSession } from "../storage/session";

interface HomeBrowseScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
  onOpenLiveChannel?: (channel: LiveTvChannel) => void;
  /** Mount the live On now row and fetch the guide. */
  showOnNow?: boolean;
  /**
   * Reserve the On now slot (skeleton only) while the Live TV probe is still
   * pending. Prevents the late insert that caused Home CLS.
   */
  reserveOnNow?: boolean;
}

/* Only ~2 rows are visible at launch (rows grow with ui-scale on 4K/8K panels),
 * and every skeleton card is mounted then torn down when data lands. */
const SKELETON_ROW_COUNT = 2;
const SKELETON_CARD_COUNT = 6;
/** Rows mounted in the first commit when there is no cache. */
const INITIAL_ROW_COUNT = 1;
/**
 * With a warm cache the first viewport already has real content — mount enough
 * rows to cover it so IntersectionObserver does not drip-feed the fold.
 */
const CACHED_INITIAL_ROW_COUNT = 3;
const ROW_MOUNT_CHUNK = 2;
/**
 * Mount a row once its reserved slot comes within this much of the viewport.
 * Must be pixels: IntersectionObserver % margins follow CSS margin rules where
 * percentages are relative to the root WIDTH, so "60%" was >1 viewport tall on
 * 16:9 and mounted almost every Home row immediately.
 */
const ROW_PREFETCH_MARGIN = "280px 0px";
/** How long entry focus waits for On now before settling on the first row. */
const ON_NOW_FOCUS_GRACE_MS = 700;

/** How many images in the first row decode eagerly; the rest stay lazy. */
const EAGER_IMAGE_COUNT = 2;

/** Cheap equality for skipping a no-op Home refresh that would still re-render. */
export function homeSectionsSignature(sections: HomeSection[]): string {
  return sections
    .map((section) => {
      const items = section.items
        .map(
          (item) =>
            `${item.content_id}:${item.position_seconds ?? ""}:${item.poster_url ?? ""}:${item.backdrop_url ?? ""}`,
        )
        .join(",");
      return `${section.id}:${section.featured ? 1 : 0}:${section.title}:${items}`;
    })
    .join("|");
}

function featuredLeadId(sections: HomeSection[]): string | null {
  const featured = sections.find((section) => section.featured);
  return featured?.items[0]?.content_id ?? null;
}

function nonFeaturedRowCount(sections: HomeSection[]): number {
  return sections.reduce((count, section) => count + (section.featured ? 0 : 1), 0);
}

/**
 * Keep rows the user already scrolled into view across a background refresh.
 * Resetting to INITIAL_ROW_COUNT unmounted Continue Watching mid-session and
 * stole focus back to the top of the page.
 */
export function reconcileMountedRows(
  prev: ReadonlySet<number>,
  rowCount: number,
  ensureCount: number = INITIAL_ROW_COUNT,
): ReadonlySet<number> {
  if (rowCount <= 0) return prev.size === 0 ? prev : new Set();
  const next = new Set<number>();
  for (const index of prev) {
    if (index >= 0 && index < rowCount) next.add(index);
  }
  for (let i = 0; i < Math.min(ensureCount, rowCount); i++) next.add(i);
  if (next.size === prev.size) {
    let same = true;
    for (const index of next) {
      if (!prev.has(index)) {
        same = false;
        break;
      }
    }
    if (same) return prev;
  }
  return next;
}

interface HomeRowProps {
  section: HomeSection;
  variant: MediaRowVariant;
  eagerCount: number;
  selectHandler: (contentId: string) => () => void;
}

/**
 * One rail, isolated from Home's state. Home re-renders whenever a row mounts,
 * On now resolves, or a row height is measured; without this boundary each of
 * those re-rendered every mounted card on the screen.
 */
const HomeRow = memo(function HomeRow({
  section,
  variant,
  eagerCount,
  selectHandler,
}: HomeRowProps) {
  const getItemKey = useCallback(
    (item: CatalogItem, itemIndex: number) => `${section.id}-${item.content_id}-${itemIndex}`,
    [section.id],
  );

  const renderItem = useCallback(
    (item: CatalogItem, itemIndex: number) => {
      const progress = catalogItemProgress(item);
      const imageLoading = itemIndex < eagerCount ? "eager" : "lazy";
      if (variant === "landscape") {
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
            imageAvifUrl={item.backdrop_url ? item.backdrop_avif_url : item.poster_avif_url}
            progress={progress}
            watched={Boolean(item.user_state?.played)}
            imageLoading={imageLoading}
            onSelect={selectHandler(item.content_id)}
          />
        );
      }
      return (
        <PosterCard
          title={item.title}
          subtitle={catalogItemSubtitle(item)}
          posterUrl={item.poster_url}
          posterAvifUrl={item.poster_avif_url}
          progress={progress}
          watched={Boolean(item.user_state?.played)}
          favorite={Boolean(item.user_state?.is_favorite)}
          imageLoading={imageLoading}
          onSelect={selectHandler(item.content_id)}
        />
      );
    },
    [variant, eagerCount, selectHandler],
  );

  return (
    <MediaRow
      title={section.title}
      variant={variant}
      items={section.items}
      getItemKey={getItemKey}
      renderItem={renderItem}
    />
  );
});

export function HomeBrowseScreen({
  session,
  onOpenItem,
  onOpenLiveChannel,
  showOnNow = false,
  reserveOnNow = false,
}: HomeBrowseScreenProps) {
  // Seed from the previous launch so the first paint shows real rows instead of
  // shimmer while the request completes.
  const cachedSections = useRef<HomeSection[] | null>(null);
  if (cachedSections.current === null) {
    cachedSections.current = loadCachedHomeSections(session.serverUrl, session.profileId) ?? [];
  }
  const [sections, setSections] = useState<HomeSection[]>(() => cachedSections.current ?? []);
  const [loading, setLoading] = useState(() => (cachedSections.current?.length ?? 0) === 0);
  const [error, setError] = useState<string | null>(null);
  const [heroIndex, setHeroIndex] = useState(0);
  const featuredLeadRef = useRef<string | null>(featuredLeadId(cachedSections.current ?? []));
  const [mountedRows, setMountedRows] = useState<ReadonlySet<number>>(() => {
    const cachedCount = nonFeaturedRowCount(cachedSections.current ?? []);
    const initial =
      cachedCount > 0
        ? Math.min(cachedCount, Math.max(INITIAL_ROW_COUNT, CACHED_INITIAL_ROW_COUNT))
        : INITIAL_ROW_COUNT;
    return new Set(Array.from({ length: initial }, (_, index) => index));
  });
  const [onNowStatus, setOnNowStatus] = useState<OnNowStatus>("loading");
  const paneRef = useRef<HTMLElement>(null);
  const rowObserverRef = useRef<IntersectionObserver | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setError(null);
      try {
        const next = await fetchHomeSections(session);
        if (!cancelled) {
          const populated = next.filter((s) => s.items.length > 0);
          const rowCount = nonFeaturedRowCount(populated);
          const nextLead = featuredLeadId(populated);
          setSections((prev) =>
            homeSectionsSignature(prev) === homeSectionsSignature(populated) ? prev : populated,
          );
          // Only rewind the hero when the featured title actually changed.
          if (featuredLeadRef.current !== nextLead) {
            featuredLeadRef.current = nextLead;
            setHeroIndex(0);
          }
          // Never collapse already-mounted rows — that is what made Continue
          // Watching disappear mid-scroll and jump focus back to the top.
          setMountedRows((prev) => reconcileMountedRows(prev, rowCount));
          saveCachedHomeSections(populated, session.serverUrl, session.profileId);
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

  const expectOnNow = (showOnNow || reserveOnNow) && onOpenLiveChannel != null;
  const handleOnNowStatus = useCallback((status: OnNowStatus) => setOnNowStatus(status), []);
  useEffect(() => {
    // Reserve mode has no fetcher; keep status at loading so entry focus waits
    // the same grace window as a real On now row.
    if (reserveOnNow && !showOnNow) setOnNowStatus("loading");
  }, [reserveOnNow, showOnNow]);
  const selectHandler = useStableItemSelect(onOpenItem);

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
        // Only grow (or first-measure). Shrinking reserved height when a row
        // remounts is a common CLS source on TV.
        const previous = prev[variant];
        if (height > 0 && (previous == null || height > previous)) {
          next = { ...next, [variant]: height };
        }
      }
      return next;
    });
  }, [loading, mountedRows, rows.length]);

  const reservedHeight = (variant: MediaRowVariant): string | number =>
    rowHeights[variant] ?? mediaRowMinHeight(variant);

  const mountRow = useCallback((index: number) => {
    setMountedRows((prev) => {
      if (prev.has(index)) return prev;
      const next = new Set(prev);
      next.add(index);
      return next;
    });
  }, []);

  const hasIntersectionObserver = typeof IntersectionObserver !== "undefined";

  /** Observe a reserved slot so its row mounts just before it scrolls into view. */
  const rowSlotRef = useCallback(
    (node: HTMLElement | null) => {
      if (!node || !hasIntersectionObserver) return;
      if (!rowObserverRef.current) {
        rowObserverRef.current = new IntersectionObserver(
          (entries) => {
            for (const entry of entries) {
              if (!entry.isIntersecting) continue;
              const index = Number((entry.target as HTMLElement).dataset.rowIndex);
              if (Number.isFinite(index)) mountRow(index);
            }
          },
          { rootMargin: ROW_PREFETCH_MARGIN },
        );
      }
      rowObserverRef.current.observe(node);
    },
    [hasIntersectionObserver, mountRow],
  );

  useEffect(() => {
    return () => {
      rowObserverRef.current?.disconnect();
      rowObserverRef.current = null;
    };
  }, []);

  // Without IntersectionObserver, fall back to adding a chunk of rows per frame.
  useEffect(() => {
    if (hasIntersectionObserver || loading) return;
    if (mountedRows.size >= rows.length) return;
    const handle = window.requestAnimationFrame(() => {
      setMountedRows((prev) => {
        const next = new Set(prev);
        for (let added = 0; added < ROW_MOUNT_CHUNK; added++) next.add(next.size);
        return next;
      });
    });
    return () => window.cancelAnimationFrame(handle);
  }, [hasIntersectionObserver, loading, mountedRows, rows.length]);

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

  // Focus parked by this screen, so a late On now row can still claim it. Any
  // remote press clears it and the user keeps their place.
  const parkedFocusRef = useRef<HTMLElement | null>(null);
  useEffect(() => {
    const clear = () => {
      parkedFocusRef.current = null;
    };
    window.addEventListener("keydown", clear, { once: true });
    return () => window.removeEventListener("keydown", clear);
  }, []);

  useEffect(() => {
    if (loading || error || featured) return;
    const pane = paneRef.current;
    if (!pane) return;
    const active = document.activeElement;
    const parked = parkedFocusRef.current;
    const userHasFocus =
      active instanceof HTMLElement && active !== document.body && pane.contains(active);
    // Hold off while On now may still arrive above the rows, but never leave the
    // screen unfocused for long — the grace timer releases the wait.
    if (awaitingOnNow && !userHasFocus) return;
    // Once On now fills, take over focus the app parked on a row below it.
    if (userHasFocus && active !== parked) return;

    const first = pane.querySelector<HTMLElement>(
      'button:not([disabled]), [tabindex]:not([tabindex="-1"])',
    );
    if (!first || first === active) return;
    first.focus({ preventScroll: true });
    parkedFocusRef.current = first;
  }, [loading, error, featured, awaitingOnNow, rows.length, onNowStatus, mountedRows]);

  return (
    <section className="browse-pane browse-pane--home" ref={paneRef}>
      {loading ? (
        <>
          <div className="home-hero home-hero--skeleton" aria-hidden="true" />
          {Array.from({ length: SKELETON_ROW_COUNT }).map((_, rowIndex) => (
            <MediaRow key={`home-skel-${rowIndex}`} title="" skeleton>
              {Array.from({ length: SKELETON_CARD_COUNT }).map((__, cardIndex) => (
                <div
                  key={`home-skel-${rowIndex}-${cardIndex}`}
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
          ))}
        </>
      ) : null}

      {error && sections.length === 0 ? (
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

      {!loading && reserveOnNow && !showOnNow && onOpenLiveChannel ? <LiveTvOnNowSkeleton /> : null}

      {!loading && showOnNow && onOpenLiveChannel ? (
        <LiveTvOnNowRow
          session={session}
          onOpenChannel={onOpenLiveChannel}
          onStatusChange={handleOnNowStatus}
        />
      ) : null}

      {!loading
        ? rows.map((section, sectionIndex) => {
            const landscape = usesLandscapeCards(section.section_type, section.items);
            const variant: MediaRowVariant = landscape ? "landscape" : "poster";
            if (!mountedRows.has(sectionIndex)) {
              return (
                <div
                  key={section.id || section.title}
                  ref={rowSlotRef}
                  data-row-index={sectionIndex}
                  className={`media-row media-row--${variant} media-row--deferred`}
                  style={{ minHeight: reservedHeight(variant) }}
                  aria-hidden="true"
                />
              );
            }
            return (
              <HomeRow
                key={section.id || section.title}
                section={section}
                variant={variant}
                eagerCount={sectionIndex === 0 ? EAGER_IMAGE_COUNT : 0}
                selectHandler={selectHandler}
              />
            );
          })
        : null}
    </section>
  );
}
