import { useEffect, useMemo, useState } from "react";
import { ApiError } from "../api/client";
import { fetchHomeSections, type HomeSection } from "../api/home";
import { HomeHero } from "../components/HomeHero";
import { LandscapeCard } from "../components/LandscapeCard";
import { MediaRow } from "../components/MediaRow";
import { PosterCard } from "../components/PosterCard";
import { catalogItemProgress, catalogItemSubtitle, usesLandscapeCards } from "../lib/browseCards";
import { formatRuntimeSeconds } from "../lib/detailMetadata";
import type { PrairieSession } from "../storage/session";

interface HomeBrowseScreenProps {
  session: PrairieSession;
  onOpenItem: (contentId: string) => void;
}

const SKELETON_ROW_COUNT = 4;
const SKELETON_CARD_COUNT = 8;

export function HomeBrowseScreen({ session, onOpenItem }: HomeBrowseScreenProps) {
  const [sections, setSections] = useState<HomeSection[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [heroIndex, setHeroIndex] = useState(0);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      try {
        const next = await fetchHomeSections(session);
        if (!cancelled) {
          setSections(next.filter((s) => s.items.length > 0));
          setHeroIndex(0);
        }
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

  const featured = useMemo(() => sections.find((section) => section.featured) ?? null, [sections]);
  const rows = useMemo(
    () => sections.filter((section) => section !== featured),
    [sections, featured],
  );

  return (
    <section className="browse-pane browse-pane--home">
      {loading ? (
        <>
          <div className="home-hero home-hero--skeleton" aria-hidden="true" />
          {Array.from({ length: SKELETON_ROW_COUNT }).map((_, rowIndex) => (
            <MediaRow key={`home-skel-${rowIndex}`} title="" skeleton>
              {Array.from({ length: SKELETON_CARD_COUNT }).map((__, cardIndex) => (
                <PosterCard
                  key={`home-skel-${rowIndex}-${cardIndex}`}
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
          ))}
        </>
      ) : null}

      {error ? (
        <p className="form-error" role="alert">
          {error}
        </p>
      ) : null}

      {!loading && !error && sections.length === 0 ? (
        <div className="browse-empty">
          <h1 className="browse-title">Home</h1>
          <p className="muted">No home rows yet — browse Libraries to find something to play.</p>
        </div>
      ) : null}

      {!loading && featured ? (
        <HomeHero
          items={featured.items}
          index={heroIndex}
          onIndexChange={setHeroIndex}
          onOpenItem={onOpenItem}
        />
      ) : null}

      {!loading
        ? rows.map((section, sectionIndex) => {
            const landscape = usesLandscapeCards(section.section_type, section.items);
            return (
              <MediaRow key={section.id || section.title} title={section.title}>
                {section.items.map((item, itemIndex) => {
                  const progress = catalogItemProgress(item);
                  const autoFocus = !featured && sectionIndex === 0 && itemIndex === 0;
                  if (landscape) {
                    const remaining =
                      item.duration_seconds != null && item.position_seconds != null
                        ? formatRuntimeSeconds(item.duration_seconds - item.position_seconds)
                        : null;
                    return (
                      <LandscapeCard
                        key={`${section.id}-${item.content_id}-${itemIndex}`}
                        title={item.title}
                        subtitle={
                          item.series_title
                            ? `${item.series_title}${
                                item.season_number != null && item.episode_number != null
                                  ? ` · S${item.season_number}E${item.episode_number}`
                                  : ""
                              }`
                            : catalogItemSubtitle(item)
                        }
                        meta={remaining ? `${remaining} left` : null}
                        imageUrl={item.backdrop_url || item.poster_url}
                        progress={progress}
                        watched={Boolean(item.user_state?.played)}
                        imageLoading={sectionIndex === 0 && itemIndex < 4 ? "eager" : "lazy"}
                        autoFocus={autoFocus}
                        onSelect={() => onOpenItem(item.content_id)}
                      />
                    );
                  }
                  return (
                    <PosterCard
                      key={`${section.id}-${item.content_id}-${itemIndex}`}
                      title={item.title}
                      subtitle={catalogItemSubtitle(item)}
                      posterUrl={item.poster_url}
                      progress={progress}
                      watched={Boolean(item.user_state?.played)}
                      favorite={Boolean(item.user_state?.is_favorite)}
                      imageLoading={sectionIndex === 0 && itemIndex < 6 ? "eager" : "lazy"}
                      autoFocus={autoFocus}
                      onSelect={() => onOpenItem(item.content_id)}
                    />
                  );
                })}
              </MediaRow>
            );
          })
        : null}
    </section>
  );
}
