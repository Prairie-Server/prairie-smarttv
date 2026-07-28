import { ArrowLeft, MoreHorizontal } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import { PosterGrid } from "../components/PosterGrid";
import { useStableItemOpen } from "../hooks/useStableItemOpen";
import { useBackKey } from "../focus/useBackKey";
import { catalogItemSubtitle } from "../lib/browseCards";
import type { PrairieSession } from "../storage/session";

interface CollectionBrowseScreenProps {
  session: PrairieSession;
  title: string;
  collectionId: string;
  libraryId?: number;
  onBack: () => void;
  onOpenItem: (contentId: string, seed?: CatalogItem) => void;
}

export function CollectionBrowseScreen({
  session,
  title,
  collectionId,
  libraryId,
  onBack,
  onOpenItem,
}: CollectionBrowseScreenProps) {
  const selectItem = useStableItemOpen(onOpenItem);
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [snapshot, setSnapshot] = useState<string | undefined>();
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const handleBack = useCallback(() => onBack(), [onBack]);
  useBackKey(handleBack);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          source: libraryId != null ? "library_collection" : "user_collection",
          collectionId,
          libraryId,
          offset: 0,
          limit: 80,
        });
        if (!cancelled) {
          setItems(page.items);
          setHasMore(Boolean(page.has_more));
          setSnapshot(page.snapshot);
        }
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load collection");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, collectionId, libraryId]);

  async function loadMore() {
    setLoadingMore(true);
    setError(null);
    try {
      const page = await fetchCatalog(session, {
        source: libraryId != null ? "library_collection" : "user_collection",
        collectionId,
        libraryId,
        offset: items.length,
        limit: 80,
        snapshot,
      });
      setItems((prev) => [...prev, ...page.items]);
      setHasMore(Boolean(page.has_more));
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
          <p className="eyebrow">Collection</p>
          <h1 className="browse-title">{title}</h1>
          {!loading ? (
            <p className="muted">
              {items.length}
              {hasMore ? "+" : ""} title{items.length === 1 ? "" : "s"}
            </p>
          ) : null}
        </div>
        <FocusButton variant="ghost" icon={<ArrowLeft />} onClick={onBack}>
          Back
        </FocusButton>
      </div>
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && !error && items.length === 0 ? (
        <p className="muted">This collection is empty.</p>
      ) : null}
      <PosterGrid>
        {loading
          ? Array.from({ length: 12 }).map((_, index) => (
              <PosterCard
                key={`col-skel-${index}`}
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
                posterAvifUrl={item.poster_avif_url}
                watched={Boolean(item.user_state?.played)}
                favorite={Boolean(item.user_state?.is_favorite)}
                imageLoading={index < 4 ? "eager" : "lazy"}
                autoFocus={index === 0}
                onSelect={selectItem(item)}
              />
            ))}
        {loadingMore
          ? Array.from({ length: 4 }).map((_, index) => (
              <PosterCard
                key={`col-more-${index}`}
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
