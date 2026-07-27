/**
 * Artwork URL helpers mirroring prairie-server web/src/lib/artworkUrl.ts.
 * Canonical cache keys stay .webp; clients pick the best sibling immediately
 * using one-time decode capability detection (see imageFormats.ts).
 *
 * Width variants live in the object key (`/original.`, `/w300.`, `/w500.`, …),
 * not query params. Path rewriting is skipped for SigV4-style signed URLs.
 */

import { getImageFormats, orderRasterCandidates } from "./imageFormats";

/**
 * Width rungs must exist in the server ladder (internal/artworkkey.VariantWidths),
 * otherwise the request 404s and the card falls back to a slower candidate:
 *   poster / still / profile -> w500, w300
 *   backdrop                 -> w1920, w1280, w300
 *   logo                     -> w500
 */

/** Poster cards (~155 CSS-px design width). */
export const POSTER_WIDTH = 300;
/** Episode stills (~280 CSS-px, upscaled on 4K panels). */
export const STILL_WIDTH = 500;
/** Backdrop-fed landscape cards (~352 CSS-px); backdrops have no w500 rung. */
export const BACKDROP_CARD_WIDTH = 300;
/**
 * Full-bleed hero backdrop. Decoded memory scales with resolution, not file
 * size: 1920×1080 costs ~8 MB of surface where 1280×720 costs ~3.7 MB, and TV
 * panels upscale the hero behind a shade layer anyway.
 */
export const BACKDROP_HERO_WIDTH = 1280;
/** Cast/crew portrait thumbnails (~120 CSS-px). */
export const PROFILE_WIDTH = 300;
/** Title logos on detail hero. */
export const LOGO_WIDTH = 500;

function pathExtension(pathname: string): string {
  const base = pathname.split("/").pop() ?? "";
  const dot = base.lastIndexOf(".");
  if (dot < 0) return "";
  return base.slice(dot);
}

/** True when rewriting the path would invalidate a cloud object signature. */
export function isSignedArtworkURL(objectPath: string): boolean {
  // AWS SigV4, GCS, generic Signature/sig, and Cloudflare WAF token (?verify=).
  return /[?&](X-Amz-Signature|X-Goog-Signature|Signature|sig|verify)=/i.test(objectPath);
}

function webPFormatSibling(objectPath: string | null | undefined, ext: ".avif" | ".png"): string {
  const trimmed = objectPath?.trim() ?? "";
  if (!trimmed) return "";
  if (isSignedArtworkURL(trimmed)) return "";

  if (trimmed.includes("://")) {
    try {
      const u = new URL(trimmed);
      const cur = pathExtension(u.pathname);
      if (cur.toLowerCase() !== ".webp") return "";
      u.pathname = `${u.pathname.slice(0, -cur.length)}${ext}`;
      return u.toString();
    } catch {
      return "";
    }
  }

  const cur = pathExtension(trimmed);
  if (cur.toLowerCase() !== ".webp") return "";
  return `${trimmed.slice(0, -cur.length)}${ext}`;
}

/**
 * Returns the AVIF sibling for a canonical WebP object key or http(s) URL.
 * Query/fragment are preserved. Non-WebP / signed inputs return "".
 */
export function webPAVIFSibling(objectPath: string | null | undefined): string {
  return webPFormatSibling(objectPath, ".avif");
}

/**
 * Returns the PNG sibling for a canonical WebP object key or http(s) URL.
 * Query/fragment are preserved. Non-WebP / signed inputs return "".
 */
export function webPPNGSibling(objectPath: string | null | undefined): string {
  return webPFormatSibling(objectPath, ".png");
}

function rewritePathWidthVariant(pathname: string, width: number): string {
  return pathname.replace(/\/(original|w\d+)(?=\.)/, `/w${width}`);
}

/**
 * Rewrites an artwork URL's width variant segment (`original` / `w300` / …)
 * to `w{width}`. Returns "" when the URL cannot safely be rewritten.
 */
export function artworkWidthVariant(objectPath: string | null | undefined, width: number): string {
  const trimmed = objectPath?.trim() ?? "";
  if (!trimmed || !Number.isFinite(width) || width <= 0) return "";
  if (isSignedArtworkURL(trimmed)) return "";

  if (trimmed.includes("://")) {
    try {
      const u = new URL(trimmed);
      const next = rewritePathWidthVariant(u.pathname, width);
      if (next === u.pathname) return "";
      u.pathname = next;
      return u.toString();
    } catch {
      return "";
    }
  }

  const next = rewritePathWidthVariant(trimmed, width);
  return next === trimmed ? "" : next;
}

/**
 * Prefer a width-variant rewrite when possible; otherwise keep the canonical URL.
 */
export function artworkSized(
  objectPath: string | null | undefined,
  width: number | null | undefined,
): string {
  const trimmed = typeof objectPath === "string" ? objectPath.trim() : "";
  if (!trimmed) return "";
  if (width == null || !Number.isFinite(width) || width <= 0) return trimmed;
  return artworkWidthVariant(trimmed, width) || trimmed;
}

/**
 * Ordered load candidates for a canonical artwork URL using the client's
 * detected raster preference (WebP/AVIF/PNG siblings when the input is WebP).
 *
 * Signed URLs return only the original — inventing AVIF/PNG siblings would
 * request an unsigned path and fail before the WebP fallback.
 */
export function artworkCandidates(objectPath: string | null | undefined): string[] {
  const trimmed = objectPath?.trim() ?? "";
  if (!trimmed) return [];
  if (isSignedArtworkURL(trimmed)) return [trimmed];

  const avif = webPAVIFSibling(trimmed);
  const png = webPPNGSibling(trimmed);
  return orderRasterCandidates({ avif, webp: trimmed, png }, getImageFormats());
}

/**
 * Candidates for a width-sized request, with the unsized ladder appended.
 * A width rung the server never generated (or a variant pruned by GC) then
 * degrades to the canonical artwork instead of showing a permanent placeholder.
 */
export function artworkSizedCandidates(
  objectPath: string | null | undefined,
  width: number | null | undefined,
): string[] {
  const trimmed = objectPath?.trim() ?? "";
  if (!trimmed) return [];
  const sized = artworkSized(trimmed, width);
  if (sized === trimmed) return artworkCandidates(trimmed);
  const seen = new Set<string>();
  const out: string[] = [];
  for (const url of [...artworkCandidates(sized), ...artworkCandidates(trimmed)]) {
    if (seen.has(url)) continue;
    seen.add(url);
    out.push(url);
  }
  return out;
}

/** Best immediate artwork URL without trial-and-error format probing. */
export function artworkPreferred(objectPath: string | null | undefined): string {
  return artworkCandidates(objectPath)[0] ?? "";
}
