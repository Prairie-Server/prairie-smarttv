import { Film, Library, Tv } from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { ApiError } from "../api/client";
import { fetchLibraries, type Library as LibraryRecord } from "../api/libraries";
import { ArtworkImage } from "../components/ArtworkImage";
import { libraryTypeLabel } from "../lib/browseCards";
import type { PrairieSession } from "../storage/session";

interface LibrariesScreenProps {
  session: PrairieSession;
  onOpenLibrary: (library: LibraryRecord) => void;
}

function libraryIcon(type: string | undefined): ReactNode {
  switch ((type ?? "").toLowerCase()) {
    case "movie":
    case "movies":
      return <Film size={28} />;
    case "series":
    case "show":
    case "tv":
      return <Tv size={28} />;
    default:
      return <Library size={28} />;
  }
}

export function LibrariesScreen({ session, onOpenLibrary }: LibrariesScreenProps) {
  const [libraries, setLibraries] = useState<LibraryRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
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
      {loading ? (
        <div className="library-grid">
          {Array.from({ length: 4 }).map((_, index) => (
            <div key={`lib-skel-${index}`} className="library-card library-card--skeleton" />
          ))}
        </div>
      ) : null}
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && !error && libraries.length === 0 ? (
        <p className="muted">No libraries are available for this profile.</p>
      ) : null}
      <div className="library-grid" data-focus-container="grid" data-focus-count={libraries.length}>
        {!loading
          ? libraries.map((library, index) => {
              const poster = library.poster_url?.trim();
              return (
                <button
                  key={library.id}
                  type="button"
                  className={`library-card${poster ? " library-card--art" : ""}`}
                  data-focus-index={index}
                  autoFocus={index === 0}
                  onClick={() => onOpenLibrary(library)}
                >
                  {poster ? (
                    <ArtworkImage
                      className="library-card__art"
                      src={poster}
                      alt=""
                      role="libraryTile"
                      loading="lazy"
                    />
                  ) : (
                    <span className="library-card__icon" aria-hidden="true">
                      {libraryIcon(library.type)}
                    </span>
                  )}
                  <span className="library-card__copy">
                    <span className="library-card__name">{library.name}</span>
                    <span className="library-card__type muted">
                      {libraryTypeLabel(library.type)}
                    </span>
                  </span>
                </button>
              );
            })
          : null}
      </div>
    </section>
  );
}
