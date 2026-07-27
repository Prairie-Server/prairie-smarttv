import type { KeyboardEvent } from "react";
import { ArtworkImage } from "./ArtworkImage";

interface PosterCardProps {
  title: string;
  subtitle?: string | null;
  posterUrl?: string | null;
  progress?: number | null;
  onSelect: () => void;
  autoFocus?: boolean;
  disabled?: boolean;
  imageLoading?: "eager" | "lazy";
  /** When true, reserve subtitle line height even if subtitle is empty (reduces CLS). */
  reserveSubtitle?: boolean;
}

export function PosterCard({
  title,
  subtitle,
  posterUrl,
  progress,
  onSelect,
  autoFocus,
  disabled,
  imageLoading = "lazy",
  reserveSubtitle = true,
}: PosterCardProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (disabled) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }

  const normalizedPosterUrl = posterUrl?.trim() ?? "";
  const hasPosterUrl = normalizedPosterUrl.length > 0;
  const subtitleText = subtitle?.trim() ?? "";

  return (
    <button
      type="button"
      className="poster-card"
      onClick={onSelect}
      onKeyDown={onKeyDown}
      autoFocus={autoFocus}
      disabled={disabled}
    >
      <div className="poster-card__art" aria-hidden="true">
        {hasPosterUrl ? (
          <ArtworkImage
            src={normalizedPosterUrl}
            alt=""
            placeholderLabel={title}
            loading={imageLoading}
            decoding="async"
            fetchPriority={imageLoading === "eager" ? "high" : "auto"}
          />
        ) : (
          <div className="poster-card__placeholder">{title.slice(0, 1) || "\u00a0"}</div>
        )}
        {progress != null && progress > 0.02 && progress < 0.95 ? (
          <div className="poster-card__progress">
            <span style={{ width: `${Math.round(progress * 100)}%` }} />
          </div>
        ) : null}
      </div>
      <div className="poster-card__meta">
        <p className="poster-card__title">{title || "\u00a0"}</p>
        {subtitleText || reserveSubtitle ? (
          <p className={`poster-card__subtitle${subtitleText ? "" : " is-empty"}`}>
            {subtitleText || "\u00a0"}
          </p>
        ) : null}
      </div>
    </button>
  );
}
