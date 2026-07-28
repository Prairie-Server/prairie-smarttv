import { memo, type KeyboardEvent } from "react";
import { Play } from "lucide-react";
import { ArtworkImage } from "./ArtworkImage";

interface LandscapeCardProps {
  title: string;
  subtitle?: string | null;
  meta?: string | null;
  imageUrl?: string | null;
  imageAvifUrl?: string | null;
  progress?: number | null;
  watched?: boolean;
  onSelect: () => void;
  autoFocus?: boolean;
  imageLoading?: "eager" | "lazy";
  /** Absolute index inside a focus container (set by MediaRow / PosterGrid). */
  "data-focus-index"?: number;
}

function LandscapeCardInner({
  title,
  subtitle,
  meta,
  imageUrl,
  imageAvifUrl,
  progress,
  watched = false,
  onSelect,
  autoFocus,
  imageLoading = "lazy",
  "data-focus-index": focusIndex,
}: LandscapeCardProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }

  const src = typeof imageUrl === "string" ? imageUrl.trim() : "";

  return (
    <button
      type="button"
      className="landscape-card"
      onClick={onSelect}
      onKeyDown={onKeyDown}
      autoFocus={autoFocus}
      data-focus-index={focusIndex}
    >
      <div className="landscape-card__art" aria-hidden="true">
        {src ? (
          <ArtworkImage
            src={src}
            avifSrc={imageAvifUrl}
            alt=""
            placeholderLabel={title}
            role="backdropCard"
            width={352}
            height={198}
            loading={imageLoading}
            decoding="async"
            fetchPriority={imageLoading === "eager" ? "high" : "auto"}
          />
        ) : (
          <div className="landscape-card__placeholder">
            <Play size={28} />
          </div>
        )}
        <span className="landscape-card__play">
          <Play size={22} fill="currentColor" />
        </span>
        {watched ? <span className="landscape-card__watched">Watched</span> : null}
        {progress != null && progress > 0.02 && progress < 0.95 ? (
          <div className="poster-card__progress">
            <span style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
        ) : null}
      </div>
      <div className="landscape-card__meta">
        {subtitle ? <p className="landscape-card__eyebrow">{subtitle}</p> : null}
        <p className="landscape-card__title">{title}</p>
        {meta ? <p className="muted landscape-card__detail">{meta}</p> : null}
      </div>
    </button>
  );
}

export const LandscapeCard = memo(LandscapeCardInner);
