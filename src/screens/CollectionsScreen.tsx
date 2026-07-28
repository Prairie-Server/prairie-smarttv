import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import {
  fetchLibraryCollections,
  fetchPersonalCollections,
  type CollectionCard,
} from "../api/collections";
import { fetchLibraries } from "../api/libraries";
import { PosterCard } from "../components/PosterCard";
import { MediaRow } from "../components/MediaRow";
import type { PrairieSession } from "../storage/session";

interface CollectionsScreenProps {
  session: PrairieSession;
  onOpenCollection: (collection: CollectionCard) => void;
}

/**
 * Concurrent per-library collection requests.
 *
 * Matches the artwork queue's reasoning: TV WebViews keep a small connection
 * pool, so beyond a handful of sockets extra requests only queue while making
 * every response slower to start.
 */
const COLLECTION_FETCH_CONCURRENCY = 4;

/** `Promise.all` with a ceiling on how many run at once, preserving order. */
async function mapWithConcurrency<T, R>(
  items: readonly T[],
  limit: number,
  run: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = Array.from({ length: items.length });
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (;;) {
      const index = next++;
      if (index >= items.length) return;
      results[index] = await run(items[index]!);
    }
  });
  await Promise.all(workers);
  return results;
}

export function CollectionsScreen({ session, onOpenCollection }: CollectionsScreenProps) {
  const [libraryCollections, setLibraryCollections] = useState<CollectionCard[]>([]);
  const [personal, setPersonal] = useState<CollectionCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        // Personal collections do not depend on the library list, so they went
        // out for no reason behind it *and* behind the whole per-library fan-out
        // — three serial legs where two suffice. Start it in the first tick and
        // join it at the end.
        const personalPromise = fetchPersonalCollections(session).catch(() => {
          // Optional depending on server features; an absent endpoint must not
          // fail the screen.
          return [] as CollectionCard[];
        });
        const libraries = await fetchLibraries(session);
        // Per-library collection requests are capped rather than fanned out at
        // once: a server with a dozen libraries would otherwise open a dozen
        // sockets on a device whose connection pool is a fraction of that, and
        // the later ones queue behind the earlier ones anyway.
        const libraryCards = (
          await mapWithConcurrency(libraries, COLLECTION_FETCH_CONCURRENCY, (library) =>
            fetchLibraryCollections(session, library.id),
          )
        ).flat();
        const personalCards = await personalPromise;
        if (cancelled) return;
        setLibraryCollections(libraryCards);
        setPersonal(personalCards);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load collections");
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
        <h1 className="browse-title">Collections</h1>
        <p className="muted">Library franchises and personal lists.</p>
      </div>
      {loading ? (
        <>
          <MediaRow title="" skeleton>
            {Array.from({ length: 8 }).map((_, index) => (
              <PosterCard
                key={`col-lib-skel-${index}`}
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
          <MediaRow title="" skeleton>
            {Array.from({ length: 6 }).map((_, index) => (
              <PosterCard
                key={`col-user-skel-${index}`}
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
        </>
      ) : null}
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && libraryCollections.length === 0 && personal.length === 0 ? (
        <p className="muted">No collections yet.</p>
      ) : null}
      {libraryCollections.length > 0 ? (
        <MediaRow
          title="Library collections"
          items={libraryCollections}
          getItemKey={(card) => `lib-${card.library_id}-${card.id}`}
          renderItem={(card, index) => (
            <PosterCard
              title={card.title ?? card.name ?? "Collection"}
              subtitle={card.item_count != null ? `${card.item_count} titles` : null}
              posterUrl={card.poster_url}
              autoFocus={index === 0}
              onSelect={() => onOpenCollection(card)}
            />
          )}
        />
      ) : null}
      {personal.length > 0 ? (
        <MediaRow
          title="Your collections"
          items={personal}
          getItemKey={(card) => `user-${card.id}`}
          renderItem={(card) => (
            <PosterCard
              title={card.title ?? card.name ?? "Collection"}
              subtitle={card.item_count != null ? `${card.item_count} titles` : null}
              posterUrl={card.poster_url}
              onSelect={() => onOpenCollection(card)}
            />
          )}
        />
      ) : null}
    </section>
  );
}
