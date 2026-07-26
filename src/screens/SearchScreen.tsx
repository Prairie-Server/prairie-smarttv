import { useEffect, useState, type FormEvent } from "react";
import { ApiError } from "../api/client";
import { fetchCatalog, type CatalogItem } from "../api/catalog";
import { FocusButton } from "../components/FocusButton";
import { PosterCard } from "../components/PosterCard";
import type { PrairieSession } from "../storage/session";

interface SearchScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
}

export function SearchScreen({ session, onOpenItem }: SearchScreenProps) {
  const [query, setQuery] = useState("");
  const [submitted, setSubmitted] = useState("");
  const [items, setItems] = useState<CatalogItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const q = submitted.trim();
    if (!q) {
      return;
    }
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const page = await fetchCatalog(session, {
          q,
          offset: 0,
          limit: 48,
        });
        if (!cancelled) setItems(page.items);
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
      setError(null);
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
        <FocusButton type="submit">Search</FocusButton>
      </form>
      {loading ? <p className="muted">Searching…</p> : null}
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && submitted && visibleItems.length === 0 ? (
        <p className="muted">No matches for “{submitted}”.</p>
      ) : null}
      <div className="poster-grid">
        {visibleItems.map((item, index) => (
          <PosterCard
            key={`${item.content_id}-${index}`}
            title={item.title}
            subtitle={item.year ? String(item.year) : item.type}
            posterUrl={item.poster_url}
            onSelect={() => onOpenItem(item.content_id)}
          />
        ))}
      </div>
    </section>
  );
}
