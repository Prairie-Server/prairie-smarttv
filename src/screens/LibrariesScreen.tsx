import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchLibraries, type Library } from "../api/libraries";
import type { PrairieSession } from "../storage/session";

interface LibrariesScreenProps {
  session: PrairieSession;
  onOpenLibrary: (library: Library) => void;
}

export function LibrariesScreen({ session, onOpenLibrary }: LibrariesScreenProps) {
  const [libraries, setLibraries] = useState<Library[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const next = await fetchLibraries(session);
        if (!cancelled) setLibraries(next);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load libraries");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  return (
    <section className="browse-pane">
      <div className="browse-pane__intro">
        <h1 className="browse-title">Libraries</h1>
        <p className="muted">Browse movies, shows, and more from your server.</p>
      </div>
      {loading ? <p className="muted">Loading…</p> : null}
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="library-grid">
        {libraries.map((library, index) => (
          <button
            key={library.id}
            type="button"
            className="library-card"
            autoFocus={index === 0}
            onClick={() => onOpenLibrary(library)}
          >
            <span className="library-card__name">{library.name}</span>
            <span className="library-card__type muted">{library.type}</span>
          </button>
        ))}
      </div>
    </section>
  );
}
