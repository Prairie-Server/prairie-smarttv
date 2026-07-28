import { memo, type KeyboardEvent } from "react";
import { Check } from "lucide-react";
import { POSTER_WIDTH } from "../lib/artworkUrl";
import { ArtworkImage } from "./ArtworkImage";

interface PosterCardProps {
  title: string;
  subtitle?: string | null;
  posterUrl?: string | null;
  posterAvifUrl?: string | null;
  progress?: number | null;
  watched?: boolean;
  favorite?: boolean;
  onSelect: () => void;
  autoFocus?: boolean;
  disabled?: boolean;
  imageLoading?: "eager" | "lazy";
  /** When true, reserve subtitle line height even if subtitle is empty (reduces CLS). */
  reserveSubtitle?: boolean;
  /** Absolute index inside a focus container (set by MediaRow / PosterGrid). */
  "data-focus-index"?: number;
}

function PosterCardInner({
  title,
  subtitle,
  posterUrl,
  posterAvifUrl,
  progress,
  watched = false,
  favorite = false,
  onSelect,
  autoFocus,
  disabled,
  imageLoading = "lazy",
  reserveSubtitle = true,
  "data-focus-index": focusIndex,
}: PosterCardProps) {
  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (disabled) return;
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      onSelect();
    }
  }

  const normalizedPosterUrl = typeof posterUrl === "string" ? posterUrl.trim() : "";
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
      data-focus-index={focusIndex}
    >
      <div className="poster-card__art" aria-hidden="true">
        {hasPosterUrl ? (
          <ArtworkImage
            src={normalizedPosterUrl}
            avifSrc={posterAvifUrl}
            alt=""
            placeholderLabel={title}
            widthHint={POSTER_WIDTH}
            width={155}
            height={232}
            loading={imageLoading}
            decoding="async"
            fetchPriority={imageLoading === "eager" ? "high" : "auto"}
          />
        ) : (
          <div className="poster-card__placeholder">{title.slice(0, 1) || "\u00a0"}</div>
        )}
        {watched ? (
          <span className="poster-card__watched" title="Watched">
            <Check size={16} strokeWidth={3} />
          </span>
        ) : null}
        {favorite && !watched ? <span className="poster-card__favorite" title="Favorite" /> : null}
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

export const PosterCard = memo(PosterCardInner);
