import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ImgHTMLAttributes,
} from "react";
import { artworkSizedCandidates } from "../lib/artworkUrl";
import { acquireImageSlot } from "../lib/imageLoadQueue";
import { resolveArtworkUrl } from "../lib/resolveArtworkUrl";
import { useServerUrl } from "../serverUrlContext";

export type ArtworkImageProps = Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
  /** Canonical artwork URL (typically a .webp object key or signed URL). */
  src: string | null | undefined;
  /** API-provided AVIF sibling — only when the object exists (e.g. poster_avif_url). */
  avifSrc?: string | null;
  /** API-provided PNG sibling. */
  pngSrc?: string | null;
  /** Optional letter/initial shown in the shimmer until the image decodes. */
  placeholderLabel?: string;
  /** Override server origin used to absolutize relative `/artwork/...` paths. */
  serverUrl?: string | null;
  /**
   * Prefer a server width variant (`/w300.`, `/w500.`, …).
   * Matches prairie-server artworkkey ladders — not a query param.
   */
  widthHint?: number | null;
};

/**
 * Loads the single best artwork URL for this device.
 *
 * Format is chosen up front from decode capability + API-provided siblings.
 * We do not invent AVIF/PNG paths or walk them on error — that cascade is too
 * slow on TV. The only retry is sized→unsized of the same chosen format.
 *
 * Relative `/artwork/...` paths are joined to the connected Prairie origin —
 * packaged TV apps are not same-origin with the server.
 */
export function ArtworkImage({
  src,
  avifSrc,
  pngSrc,
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
  const normalizedAvif = resolveArtworkUrl(avifSrc, serverUrl) || undefined;
  const normalizedPng = resolveArtworkUrl(pngSrc, serverUrl) || undefined;
  // Candidate lists cost a localStorage read + UA sniff per call; TV screens
  // mount dozens of cards, so keep it out of the per-render path.
  const candidates = useMemo(
    () =>
      artworkSizedCandidates(normalizedSrc, widthHint, {
        avif: normalizedAvif,
        png: normalizedPng,
      }),
    [normalizedSrc, normalizedAvif, normalizedPng, widthHint],
  );
  const [failedCount, setFailedCount] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const prevKey = useRef<string>("");
  const imgRef = useRef<HTMLImageElement | null>(null);
  const releaseSlotRef = useRef<(() => void) | null>(null);
  const sourceKey = `${normalizedSrc ?? ""}|${normalizedAvif ?? ""}|${normalizedPng ?? ""}|${widthHint ?? ""}`;
  const isSrcChange = prevKey.current !== sourceKey;

  if (isSrcChange) prevKey.current = sourceKey;

  useEffect(() => {
    setFailedCount(0);
    setLoaded(false);
  }, [sourceKey]);

  const effectiveFailedCount = isSrcChange ? 0 : failedCount;
  const current =
    candidates.length > 0 ? candidates[Math.min(effectiveFailedCount, candidates.length - 1)]! : "";

  // Eager artwork still uses the queue (uncapped parallel decode locks D-pad
  // input on TV) but jumps the priority lane ahead of lazy posters.
  const eager = rest.loading === "eager";
  const [slotGranted, setSlotGranted] = useState(false);
  useEffect(() => {
    if (!current) return;
    setSlotGranted(false);
    const release = acquireImageSlot(() => setSlotGranted(true), { priority: eager });
    releaseSlotRef.current = release;
    return () => {
      release();
      releaseSlotRef.current = null;
    };
  }, [current, eager]);

  const releaseSlot = useCallback(() => {
    releaseSlotRef.current?.();
    releaseSlotRef.current = null;
  }, []);

  useLayoutEffect(() => {
    if (!current) return;
    const img = imgRef.current;
    if (img?.complete && img.naturalWidth > 0) {
      setLoaded(true);
      releaseSlot();
    }
  }, [current, releaseSlot]);

  if (candidates.length === 0) return null;

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
        src={slotGranted ? current : undefined}
        alt={alt}
        width={width}
        height={height}
        style={imgStyle}
        onLoad={(event) => {
          setLoaded(true);
          releaseSlot();
          onLoad?.(event);
        }}
        onError={(event) => {
          releaseSlot();
          // Only sized→unsized of the same format — never a format cascade.
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
