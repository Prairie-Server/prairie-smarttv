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
        const libraries = await fetchLibraries(session);
        const libraryCards = (
          await Promise.all(
            libraries.map((library) => fetchLibraryCollections(session, library.id)),
          )
        ).flat();
        let personalCards: CollectionCard[] = [];
        try {
          personalCards = await fetchPersonalCollections(session);
        } catch {
          // Personal collections are optional depending on server features.
          personalCards = [];
        }
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
