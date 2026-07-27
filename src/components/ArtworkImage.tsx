import { useEffect, useRef, useState, type ImgHTMLAttributes } from "react";
import { artworkCandidates } from "../lib/artworkUrl";

export type ArtworkImageProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  /** Canonical artwork URL (typically a .webp object key or signed URL). */
  src: string | null | undefined;
};

/**
 * Prefers the AVIF sibling of a canonical WebP artwork URL, then WebP, then
 * PNG when earlier formats are missing or fail to load (legacy Tizen / webOS,
 * missing siblings).
 */
export function ArtworkImage({ src, alt, onError, onLoad, ...rest }: ArtworkImageProps) {
  const normalizedSrc = src?.trim();
  const candidates = artworkCandidates(normalizedSrc);
  const [failedCount, setFailedCount] = useState(0);
  const prevNormalizedSrc = useRef<string | undefined>(undefined);
  const isSrcChange = prevNormalizedSrc.current !== normalizedSrc;

  // Update ref during render (safe, doesn't trigger rerenders).
  if (isSrcChange) prevNormalizedSrc.current = normalizedSrc;

  useEffect(() => {
    // Reset the fallback chain when the canonical artwork URL changes.
    setFailedCount(0);
  }, [normalizedSrc]);

  if (!normalizedSrc || candidates.length === 0) return null;

  const effectiveFailedCount = isSrcChange ? 0 : failedCount;
  const index = Math.min(effectiveFailedCount, candidates.length - 1);
  const current = candidates[index]!;

  return (
    <img
      {...rest}
      src={current}
      alt={alt}
      onLoad={onLoad}
      onError={(event) => {
        if (failedCount < candidates.length - 1) {
          setFailedCount((n) => n + 1);
          return;
        }
        onError?.(event);
      }}
    />
  );
}
