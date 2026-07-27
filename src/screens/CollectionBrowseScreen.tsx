import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import type { PrairieSession } from "../storage/session";

interface CollectionBrowseScreenProps {
  session: PrairieSession;
  title: string;
  collectionId: string;
  libraryId?: number;
  onBack: () => void;
  onOpenItem: (contentId: string) => void;
}

export function CollectionBrowseScreen({
  session,
  title,
  collectionId,
  libraryId,
  onBack,
  onOpenItem,
}: CollectionBrowseScreenProps) {
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          source: libraryId != null ? "library_collection" : "user_collection",
          collectionId,
          offset: 0,
          limit: 80,
        });
        if (!cancelled) setItems(page.items);
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

  return (
    <section className="browse-pane">
      <div className="browse-pane__intro browse-pane__intro--row">
        <div>
          <p className="eyebrow">Collection</p>
          <h1 className="browse-title">{title}</h1>
        </div>
        <FocusButton variant="ghost" onClick={onBack}>
          Back
        </FocusButton>
      </div>
      {loading ? <p className="muted">Loading…</p> : null}
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      <div className="poster-grid">
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
                subtitle={item.year ? String(item.year) : item.type}
                posterUrl={item.poster_url}
                imageLoading={index < 12 ? "eager" : "lazy"}
                autoFocus={index === 0}
                onSelect={() => onOpenItem(item.content_id)}
              />
            ))}
      </div>
    </section>
  );
}
