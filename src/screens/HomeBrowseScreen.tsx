import { useEffect, useState } from "react";
import { ApiError } from "../api/client";
import { fetchHomeSections, type HomeSection } from "../api/home";
import { MediaRow } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import type { PrairieSession } from "../storage/session";

interface HomeBrowseScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
}

function itemSubtitle(item: {
  type?: string;
  year?: number | null;
  series_title?: string | null;
  season_number?: number | null;
  episode_number?: number | null;
}): string | null {
  if (item.series_title && item.season_number != null && item.episode_number != null) {
    return `${item.series_title} · S${item.season_number}E${item.episode_number}`;
  }
  if (item.year) return String(item.year);
  if (item.type) return item.type;
  return null;
}

function itemProgress(item: {
  position_seconds?: number | null;
  duration_seconds?: number | null;
}): number | null {
  const pos = item.position_seconds;
  const dur = item.duration_seconds;
  if (pos == null || dur == null || dur <= 0) return null;
  return Math.min(1, Math.max(0, pos / dur));
}

export function HomeBrowseScreen({ session, onOpenItem }: HomeBrowseScreenProps) {
  const [sections, setSections] = useState<HomeSection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError(null);
      try {
        const next = await fetchHomeSections(session);
        if (!cancelled) setSections(next.filter((s) => s.items.length > 0));
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof ApiError ? err.message : "Could not load home");
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
        <h1 className="browse-title">Home</h1>
        <p className="muted">Continue watching and fresh arrivals from your Prairie libraries.</p>
      </div>
      {loading ? <p className="muted">Loading…</p> : null}
      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}
      {!loading && !error && sections.length === 0 ? (
        <p className="muted">No home rows yet — browse Libraries to find something to play.</p>
      ) : null}
      {sections.map((section, sectionIndex) => (
        <MediaRow key={section.id || section.title} title={section.title}>
          {section.items.map((item, itemIndex) => (
            <PosterCard
              key={`${section.id}-${item.content_id}-${itemIndex}`}
              title={item.title}
              subtitle={itemSubtitle(item)}
              posterUrl={item.poster_url}
              progress={itemProgress(item)}
              autoFocus={sectionIndex === 0 && itemIndex === 0}
              onSelect={() => onOpenItem(item.content_id)}
            />
          ))}
        </MediaRow>
      ))}
    </section>
  );
}
