/**
 * Artwork URL helpers mirroring prairie-server web/src/lib/artworkUrl.ts.
 *
 * Canonical cache keys stay .webp. Format choice is decided up front from
 * decode capability + URLs the API actually supplied — we never invent AVIF/PNG
 * siblings and walk them on 404. That cascade is what made posters feel slow.
 *
 * Width variants live in the object key (`/original.`, `/w300.`, `/w500.`, …),
 * not query params. Path rewriting is skipped for SigV4-style signed URLs.
 */

import { getImageFormats, orderRasterCandidates } from "./imageFormats";

/**
 * Width rungs must exist in the server ladder (internal/artworkkey.VariantWidths):
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
 *
 * @deprecated Prefer API-provided `*_avif_url` fields. Inventing siblings leads
 * to 404→retry cascades on TV.
 */
export function webPAVIFSibling(objectPath: string | null | undefined): string {
  return webPFormatSibling(objectPath, ".avif");
}

/**
 * Returns the PNG sibling for a canonical WebP object key or http(s) URL.
 * Query/fragment are preserved. Non-WebP / signed inputs return "".
 *
 * @deprecated Prefer API-provided format siblings. Inventing siblings is slow.
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

export type ArtworkFormatSources = {
  /** Pre-signed / API-provided AVIF sibling (only when the object exists). */
  avif?: string | null;
  /** Pre-signed / API-provided PNG sibling. */
  png?: string | null;
};

/**
 * The single best artwork URL for this client among URLs we know exist.
 *
 * Never invents AVIF/PNG siblings from a WebP path — that 404 cascade is what
 * made Home/detail posters crawl. Without explicit siblings, the canonical
 * WebP (or whatever the API returned) is the answer.
 */
export function artworkCandidates(
  objectPath: string | null | undefined,
  formats?: ArtworkFormatSources,
): string[] {
  const trimmed = objectPath?.trim() ?? "";
  const avif = formats?.avif?.trim() ?? "";
  const png = formats?.png?.trim() ?? "";
  if (avif || png) {
    const ordered = orderRasterCandidates({ avif, webp: trimmed, png }, getImageFormats());
    const best = ordered[0] ?? trimmed;
    return best ? [best] : [];
  }
  if (!trimmed) return [];
  return [trimmed];
}

/**
 * Width-sized load list for one chosen format.
 *
 * At most two URLs: the sized variant, then the unsized original of the *same*
 * format if a width rewrite applied. No AVIF→WebP→PNG walk.
 */
export function artworkSizedCandidates(
  objectPath: string | null | undefined,
  width: number | null | undefined,
  formats?: ArtworkFormatSources,
): string[] {
  const preferred = artworkPreferred(objectPath, formats);
  if (!preferred) return [];
  const sized = artworkSized(preferred, width);
  if (sized && sized !== preferred) return [sized, preferred];
  return [preferred];
}

/** Best immediate artwork URL without trial-and-error format probing. */
export function artworkPreferred(
  objectPath: string | null | undefined,
  formats?: ArtworkFormatSources,
): string {
  return artworkCandidates(objectPath, formats)[0] ?? "";
}
