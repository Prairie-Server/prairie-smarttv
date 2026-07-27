import { useEffect, useRef, useState, type CSSProperties, type ImgHTMLAttributes } from "react";
import { artworkCandidates } from "../lib/artworkUrl";

export type ArtworkImageProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  /** Canonical artwork URL (typically a .webp object key or signed URL). */
  src: string | null | undefined;
  /** Optional letter/initial shown in the shimmer until the image decodes. */
  placeholderLabel?: string;
};

/**
 * Prefers the AVIF sibling of a canonical WebP artwork URL, then WebP, then
 * PNG when earlier formats are missing or fail to load (legacy Tizen / webOS,
 * missing siblings). Keeps a sized placeholder visible until the first
 * successful decode to avoid empty→image layout flashes.
 */
export function ArtworkImage({
  src,
  alt,
  onError,
  onLoad,
  placeholderLabel = "",
  className,
  style,
  ...rest
}: ArtworkImageProps) {
  const normalizedSrc = src?.trim();
  const candidates = artworkCandidates(normalizedSrc);
  const [failedCount, setFailedCount] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const prevNormalizedSrc = useRef<string | undefined>(undefined);
  const isSrcChange = prevNormalizedSrc.current !== normalizedSrc;

  // Update ref during render (safe, doesn't trigger rerenders).
  if (isSrcChange) prevNormalizedSrc.current = normalizedSrc;

  useEffect(() => {
    // Reset the fallback chain when the canonical artwork URL changes.
    setFailedCount(0);
    setLoaded(false);
  }, [normalizedSrc]);

  if (!normalizedSrc || candidates.length === 0) return null;

  const effectiveFailedCount = isSrcChange ? 0 : failedCount;
  const index = Math.min(effectiveFailedCount, candidates.length - 1);
  const current = candidates[index]!;
  const showPlaceholder = !loaded;
  const imgStyle: CSSProperties = {
    ...(typeof style === "object" && style ? style : null),
    opacity: loaded ? 1 : 0,
  };

  return (
    <div className={["artwork-image", className].filter(Boolean).join(" ")}>
      {showPlaceholder ? (
        <div className="poster-card__placeholder artwork-image__placeholder" aria-hidden="true">
          {placeholderLabel.slice(0, 1)}
        </div>
      ) : null}
      <img
        {...rest}
        className="artwork-image__img"
        src={current}
        alt={alt}
        style={imgStyle}
        onLoad={(event) => {
          setLoaded(true);
          onLoad?.(event);
        }}
        onError={(event) => {
          if (failedCount < candidates.length - 1) {
            setFailedCount((n) => n + 1);
            setLoaded(false);
            return;
          }
          onError?.(event);
        }}
      />
    </div>
  );
}
