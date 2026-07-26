import type { KeyboardEvent } from "react";
import { ArtworkImage } from "./ArtworkImage";

interface PosterCardProps {
  title: string;
  subtitle?: string | null;
  posterUrl?: string | null;
  progress?: number | null;
  onSelect: () => void;
  autoFocus?: boolean;
}

export function PosterCard({
  title,
  subtitle,
  posterUrl,
  progress,
  onSelect,
  autoFocus,
}: PosterCardProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }

  return (
    <button
      type="button"
      className="poster-card"
      onClick={onSelect}
      onKeyDown={onKeyDown}
      autoFocus={autoFocus}
    >
      <div className="poster-card__art" aria-hidden="true">
        {posterUrl ? (
          <ArtworkImage src={posterUrl} alt="" loading="lazy" />
        ) : (
          <div className="poster-card__placeholder">{title.slice(0, 1)}</div>
        )}
        {progress != null && progress > 0.02 && progress < 0.95 ? (
          <div className="poster-card__progress">
            <span style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
        ) : null}
      </div>
      <div className="poster-card__meta">
        <p className="poster-card__title">{title}</p>
        {subtitle ? <p className="poster-card__subtitle">{subtitle}</p> : null}
      </div>
    </button>
  );
}
