import { MoreHorizontal, Search } from "lucide-react";
import { useEffect, useState, type FormEvent } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import { catalogItemSubtitle } from "../lib/browseCards";
import type { PrairieSession } from "../storage/session";

interface SearchScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
}

export function SearchScreen({ session, onOpenItem }: SearchScreenProps) {
  const [query, setQuery] = useState("");
  const [submitted, setSubmitted] = useState("");
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [snapshot, setSnapshot] = useState<string | undefined>();
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const q = submitted.trim();
    if (!q) {
      return;
    }
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          q,
          offset: 0,
          limit: 48,
        });
        if (!cancelled) {
          setItems(page.items);
          setHasMore(Boolean(page.has_more));
          setSnapshot(page.snapshot);
        }
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Search failed");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session, submitted]);

  function onSubmit(event: FormEvent) {
    event.preventDefault();
    const next = query.trim();
    setSubmitted(next);
    if (!next) {
      setLoading(false);
      setItems([]);
      setHasMore(false);
      setSnapshot(undefined);
      setError(null);
    }
  }

  async function loadMore() {
    const q = submitted.trim();
    if (!q) return;
    setLoadingMore(true);
    setError(null);
    try {
      const page = await fetchCatalog(session, {
        q,
        offset: items.length,
        limit: 48,
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

  const visibleItems = submitted.trim() ? items : [];

  return (
    <section className="browse-pane">
      <div className="browse-pane__intro">
        <h1 className="browse-title">Search</h1>
        <p className="muted">Find movies, shows, and episodes across your libraries.</p>
      </div>
      <form className="search-form" onSubmit={onSubmit}>
        <label className="field">
          <span>Query</span>
          <input
            className="focusable"
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Title…"
          />
        </label>
        <FocusButton type="submit" icon={<Search />}>
          Search
        </FocusButton>
      </form>
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && submitted && visibleItems.length === 0 ? (
        <p className="muted">No matches for “{submitted}”.</p>
      ) : null}
      <div className="poster-grid">
        {loading && submitted.trim()
          ? Array.from({ length: 12 }).map((_, index) => (
              <PosterCard
                key={`search-skel-${index}`}
                title=""
                subtitle={null}
                posterUrl={null}
                disabled
                onSelect={() => {
                  // Disabled skeleton; no-op.
                }}
              />
            ))
          : visibleItems.map((item, index) => (
              <PosterCard
                key={`${item.content_id}-${index}`}
                title={item.title}
                subtitle={catalogItemSubtitle(item)}
                posterUrl={item.poster_url}
                watched={Boolean(item.user_state?.played)}
                favorite={Boolean(item.user_state?.is_favorite)}
                imageLoading={index < 12 ? "eager" : "lazy"}
                onSelect={() => onOpenItem(item.content_id)}
              />
            ))}
        {loadingMore
          ? Array.from({ length: 4 }).map((_, index) => (
              <PosterCard
                key={`search-more-${index}`}
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
      </div>
      {hasMore && !loading && submitted.trim() ? (
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
