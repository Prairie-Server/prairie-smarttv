import { Play } from "lucide-react";
import type { CatalogItem } from "../api/catalog";
import { ArtworkImage } from "./ArtworkImage";
import { FocusButton } from "./FocusButton";
import { catalogItemSubtitle } from "../lib/browseCards";

interface HomeHeroProps {
  items: CatalogItem[];
  index: number;
  onIndexChange: (index: number) => void;
  onOpenItem: (contentId: string, seed?: CatalogItem) => void;
  autoFocusPlay?: boolean;
}

export function HomeHero({
  items,
  index,
  onIndexChange,
  onOpenItem,
  autoFocusPlay = true,
}: HomeHeroProps) {
  if (!items.length) return null;
  const safeIndex = ((index % items.length) + items.length) % items.length;
  const item = items[safeIndex];
  if (!item) return null;

  const backdrop = item.backdrop_url?.trim() || item.poster_url?.trim() || null;
  const backdropAvif = item.backdrop_url?.trim() ? item.backdrop_avif_url : item.poster_avif_url;
  const subtitle = catalogItemSubtitle(item);
  const overview = item.overview?.trim();

  return (
    <section className="home-hero" aria-label="Featured">
      {backdrop ? (
        <ArtworkImage
          className="home-hero__art"
          src={backdrop}
          avifSrc={backdropAvif}
          alt=""
          role="backdropHero"
          loading="eager"
        />
      ) : (
        <div className="home-hero__art home-hero__art--empty" />
      )}
      <div className="home-hero__shade" />
      <div className="home-hero__content">
        <p className="eyebrow">
          Featured{items.length > 1 ? ` · ${safeIndex + 1} of ${items.length}` : ""}
        </p>
        <h1 className="home-hero__title">{item.title}</h1>
        {subtitle ? <p className="home-hero__meta">{subtitle}</p> : null}
        {overview ? <p className="home-hero__overview">{overview}</p> : null}
        <div className="row-actions">
          <FocusButton
            autoFocus={autoFocusPlay}
            icon={<Play />}
            onClick={() => onOpenItem(item.content_id, item)}
          >
            More Info
          </FocusButton>
          {items.length > 1 ? (
            <>
              <FocusButton
                variant="ghost"
                onClick={() => onIndexChange((safeIndex - 1 + items.length) % items.length)}
              >
                Prev
              </FocusButton>
              <FocusButton
                variant="ghost"
                onClick={() => onIndexChange((safeIndex + 1) % items.length)}
              >
                Next
              </FocusButton>
            </>
          ) : null}
        </div>
      </div>
    </section>
  );
}
