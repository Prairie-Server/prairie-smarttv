import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import type { PrairieSession } from "../storage/session";

interface LibraryBrowseScreenProps {
  session: PrairieSession;
  libraryId: number;
  libraryName: string;
  onBack: () => void;
  onOpenItem: (contentId: string) => void;
}

export function LibraryBrowseScreen({
  session,
  libraryId,
  libraryName,
  onBack,
  onOpenItem,
}: LibraryBrowseScreenProps) {
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [snapshot, setSnapshot] = useState<string | undefined>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          libraryId,
          offset: 0,
          limit: 60,
        });
        if (cancelled) return;
        setItems(page.items);
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
  }, [session, libraryId]);

  async function loadMore() {
    setLoading(true);
    setError(null);
    try {
      const page = await fetchCatalog(session, {
        libraryId,
        offset: items.length,
        limit: 60,
        snapshot,
      });
      setItems((prev) => [...prev, ...page.items]);
      setHasMore(Boolean(page.has_more));
      if (page.snapshot) setSnapshot(page.snapshot);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "Could not load more");
    } finally {
      setLoading(false);
    }
  }

  return (
    <section className="browse-pane">
      <div className="browse-pane__intro browse-pane__intro--row">
        <div>
          <p className="eyebrow">Library</p>
          <h1 className="browse-title">{libraryName}</h1>
        </div>
        <FocusButton variant="ghost" onClick={onBack}>
          Back
        </FocusButton>
      </div>
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      <div className="poster-grid">
        {items.map((item, index) => (
          <PosterCard
            key={`${item.content_id}-${index}`}
            title={item.title}
            subtitle={item.year ? String(item.year) : item.type}
            posterUrl={item.poster_url}
            autoFocus={index === 0}
            onSelect={() => onOpenItem(item.content_id)}
          />
        ))}
      </div>
      {loading ? <p className="muted">Loading…</p> : null}
      {hasMore && !loading ? (
        <div className="row-actions">
          <FocusButton onClick={() => void loadMore()}>Load more</FocusButton>
        </div>
      ) : null}
    </section>
  );
}
