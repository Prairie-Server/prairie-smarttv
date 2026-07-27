import { ArrowLeft, MoreHorizontal } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import { PosterGrid } from "../components/PosterGrid";
import { useBackKey } from "../focus/useBackKey";
import { catalogItemSubtitle, LIBRARY_SORT_OPTIONS } from "../lib/browseCards";
import type { PrairieSession } from "../storage/session";

interface LibraryBrowseScreenProps {
  session: PrairieSession;
  libraryId: number;
  libraryName: string;
  libraryType?: string;
  onBack: () => void;
  onOpenItem: (contentId: string) => void;
}

export function LibraryBrowseScreen({
  session,
  libraryId,
  libraryName,
  libraryType,
  onBack,
  onOpenItem,
}: LibraryBrowseScreenProps) {
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [total, setTotal] = useState<number | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [snapshot, setSnapshot] = useState<string | undefined>();
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sortIndex, setSortIndex] = useState(0);

  const sort = LIBRARY_SORT_OPTIONS[sortIndex] ?? LIBRARY_SORT_OPTIONS[0];
  const showTypeFilter = libraryType === "series" || libraryType === "show" || libraryType === "tv";
  const [typeFilter, setTypeFilter] = useState<"series" | "episode">("series");
  const effectiveType = showTypeFilter ? typeFilter : undefined;
  const handleBack = useCallback(() => onBack(), [onBack]);
  useBackKey(handleBack);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          libraryId,
          type: effectiveType,
          offset: 0,
          limit: 60,
          sort: sort.value,
          order: sort.order,
        });
        if (cancelled) return;
        setItems(page.items);
        setTotal(page.total ?? page.items.length);
        setHasMore(Boolean(page.has_more));
        setSnapshot(page.snapshot);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load library");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, libraryId, sort.value, sort.order, effectiveType]);

  async function loadMore() {
    setLoadingMore(true);
    setError(null);
    try {
      const page = await fetchCatalog(session, {
        libraryId,
        type: effectiveType,
        offset: items.length,
        limit: 60,
        snapshot,
        sort: sort.value,
        order: sort.order,
      });
      setItems((prev) => [...prev, ...page.items]);
      setHasMore(Boolean(page.has_more));
      if (page.total != null) setTotal(page.total);
      if (page.snapshot) setSnapshot(page.snapshot);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not load more");
    } finally {
      setLoadingMore(false);
    }
  }

  return (
    <section className="browse-pane">
      <div className="browse-pane__intro browse-pane__intro--row">
        <div>
          <p className="eyebrow">Library</p>
          <h1 className="browse-title">{libraryName}</h1>
          {total != null && !loading ? (
            <p className="muted">
              {total} title{total === 1 ? "" : "s"}
              {sort ? ` · Sorted by ${sort.label}` : ""}
            </p>
          ) : null}
        </div>
        <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={onBack}>
          Back
        </FocusButton>
      </div>

      <div className="browse-toolbar" role="toolbar" aria-label="Library filters">
        {LIBRARY_SORT_OPTIONS.map((option, index) => (
          <button
            key={option.value}
            type="button"
            className={`browse-chip${sortIndex === index ? " is-active" : ""}`}
            onClick={() => setSortIndex(index)}
          >
            {option.label}
          </button>
        ))}
        {showTypeFilter ? (
          <>
            <span className="browse-toolbar__divider" aria-hidden="true" />
            <button
              type="button"
              className={`browse-chip${typeFilter === "series" ? " is-active" : ""}`}
              onClick={() => setTypeFilter("series")}
            >
              Series
            </button>
            <button
              type="button"
              className={`browse-chip${typeFilter === "episode" ? " is-active" : ""}`}
              onClick={() => setTypeFilter("episode")}
            >
              Episodes
            </button>
          </>
        ) : null}
      </div>

      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}

      {!loading && !error && items.length === 0 ? (
        <p className="muted">No titles in this library yet.</p>
      ) : null}

      <PosterGrid>
        {loading
          ? Array.from({ length: 12 }).map((_, index) => (
              <PosterCard
                key={`lib-skel-${index}`}
                title=""
                subtitle={null}
                posterUrl={null}
                disabled
                onSelect={() => {
                  // Disabled skeleton; no-op.
                }}
              />
            ))
          : items.map((item, index) => (
              <PosterCard
                key={`${item.content_id}-${index}`}
                title={item.title}
                subtitle={catalogItemSubtitle(item)}
                posterUrl={item.poster_url}
                watched={Boolean(item.user_state?.played)}
                favorite={Boolean(item.user_state?.is_favorite)}
                imageLoading={index < 12 ? "eager" : "lazy"}
                autoFocus={index === 0}
                onSelect={() => onOpenItem(item.content_id)}
              />
            ))}
        {loadingMore
          ? Array.from({ length: 4 }).map((_, index) => (
              <PosterCard
                key={`lib-more-${index}`}
                title=""
                subtitle={null}
                posterUrl={null}
                disabled
                onSelect={() => {
                  // Disabled skeleton; no-op.
                }}
              />
            ))
          : null}
      </PosterGrid>
      {hasMore && !loading ? (
        <div className="row-actions">
          <FocusButton
            icon={<MoreHorizontal />}
            disabled={loadingMore}
            onClick={() => void loadMore()}
          >
            {loadingMore ? "Loading…" : "Load more"}
          </FocusButton>
        </div>
      ) : null}
    </section>
  );
}
