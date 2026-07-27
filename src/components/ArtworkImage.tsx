import {
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ImgHTMLAttributes,
} from "react";
import { artworkSizedCandidates } from "../lib/artworkUrl";
import { resolveArtworkUrl } from "../lib/resolveArtworkUrl";
import { useServerUrl } from "../serverUrlContext";

export type ArtworkImageProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  /** Canonical artwork URL (typically a .webp object key or signed URL). */
  src: string | null | undefined;
  /** Optional letter/initial shown in the shimmer until the image decodes. */
  placeholderLabel?: string;
  /** Override server origin used to absolutize relative `/artwork/...` paths. */
  serverUrl?: string | null;
  /**
   * Prefer a server width variant (`/w300.`, `/w500.`, …) before format siblings.
   * Matches prairie-server artworkkey ladders — not a query param.
   */
  widthHint?: number | null;
};

/**
 * Prefers the AVIF sibling of a canonical WebP artwork URL, then WebP, then
 * PNG when earlier formats are missing or fail to load (legacy Tizen / webOS,
 * missing siblings). Keeps a sized placeholder visible until the first
 * successful decode to avoid empty→image layout flashes.
 *
 * Relative `/artwork/...` paths are joined to the connected Prairie origin —
 * packaged TV apps are not same-origin with the server.
 */
export function ArtworkImage({
  src,
  alt,
  onError,
  onLoad,
  placeholderLabel = "",
  className,
  style,
  serverUrl: serverUrlProp,
  widthHint,
  width,
  height,
  ...rest
}: ArtworkImageProps) {
  const contextServerUrl = useServerUrl();
  const serverUrl = serverUrlProp?.trim() || contextServerUrl;
  const normalizedSrc = resolveArtworkUrl(src, serverUrl) || undefined;
  // Candidate lists cost a localStorage read + UA sniff per call; TV screens
  // mount dozens of cards, so keep it out of the per-render path.
  const candidates = useMemo(
    () => artworkSizedCandidates(normalizedSrc, widthHint),
    [normalizedSrc, widthHint],
  );
  const [failedCount, setFailedCount] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const prevNormalizedSrc = useRef<string | undefined>(undefined);
  const imgRef = useRef<HTMLImageElement | null>(null);
  const isSrcChange = prevNormalizedSrc.current !== normalizedSrc;

  if (isSrcChange) prevNormalizedSrc.current = normalizedSrc;

  useEffect(() => {
    setFailedCount(0);
    setLoaded(false);
  }, [normalizedSrc]);

  const effectiveFailedCount = isSrcChange ? 0 : failedCount;
  const current =
    normalizedSrc && candidates.length > 0
      ? candidates[Math.min(effectiveFailedCount, candidates.length - 1)]!
      : "";

  useLayoutEffect(() => {
    if (!current) return;
    const img = imgRef.current;
    if (img?.complete && img.naturalWidth > 0) {
      setLoaded(true);
    }
  }, [current]);

  if (!normalizedSrc || candidates.length === 0) return null;

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
        ref={imgRef}
        className="artwork-image__img"
        src={current}
        alt={alt}
        width={width}
        height={height}
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
