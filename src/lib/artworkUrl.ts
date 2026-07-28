/**
 * Artwork URL helpers mirroring prairie-server web/src/lib/artworkUrl.ts.
 *
 * Canonical cache keys stay .webp. Format choice is decided up front from
 * decode capability + URLs the API actually supplied — we never invent AVIF/PNG
 * siblings and walk them on 404. That cascade is what made posters feel slow.
 *
 * Width variants live in the object key (`/original.`, `/w300.`, `/w500.`, …),
 * not query params. Path rewriting is skipped for third-party signed URLs
 * (SigV4 and friends) whose signature covers the exact key, but not for this
 * server's own signature, which covers the revision — see
 * {@link isPrairieSignedArtworkURL}.
 */

import { getImageFormats, orderRasterCandidates } from "./imageFormats";

/**
 * Width rungs must exist in the server ladder (internal/artworkkey.VariantWidths):
 *   poster / still / profile -> w500, w300, w200
 *   backdrop                 -> w1920, w1280, w300
 *   logo                     -> w500
 *
 * Rungs are sized against the *rendered* CSS width, which on a TV is the design
 * width times the panel chrome scale — not the panel's pixel count. TV WebViews
 * keep a ~1920 CSS viewport even on 4K/8K and let the compositor upscale, so a
 * card grows by PANEL_CHROME_SCALE (1.28 on UHD, 1.55 on 8K), not by 2x or 4x.
 *
 * These widths decide what a TV downloads, but only against a server that signs
 * the artwork *revision* rather than the exact object key
 * (Prairie-Server/prairie-server#121). Before that change the signature covered
 * the key, `artworkWidthVariant` had to bail on every signed URL, and each
 * constant below was skipped — which is how this file spent a while looking like
 * the knob that mattered while a real TV rendered whatever rung the server chose.
 *
 * The server still chooses the rung it signs, per device class, from the
 * `X-Prairie-Device-Platform` header this client sends: see
 * `catalog.cachedImageVariantKeyFor`. That remains the floor for any client that
 * does not rewrite (older builds of this app included), so the two are kept in
 * step deliberately rather than left to drift.
 */

/**
 * Poster cards (~155 CSS-px design width, ~198 on UHD chrome scale).
 *
 * w300 decoded ~3.7x the pixels actually shown at FHD. w200 is the narrowest
 * rung the server generates and still covers the UHD rendered width, roughly
 * halving both bytes and decoded surface — which on TV is the cost that matters,
 * since decoded surface is what triggers the GC pauses that read as input lag.
 */
export const POSTER_WIDTH = 200;
/**
 * Episode stills (~280 CSS-px, ~358 on UHD chrome scale).
 *
 * Deliberately NOT dropped to the w200 rung: at 358 rendered px it would be
 * upscaled, and w300 only just covers it. Stills are also far fewer per screen
 * than poster cards, so the saving would be small and the softening visible.
 */
export const STILL_WIDTH = 500;
/** Backdrop-fed landscape cards (~352 CSS-px); backdrops have no w500 rung. */
export const BACKDROP_CARD_WIDTH = 300;
/**
 * Full-bleed hero backdrop. Decoded memory scales with resolution, not file
 * size: 1920×1080 costs ~8 MB of surface where 1280×720 costs ~3.7 MB, and TV
 * panels upscale the hero behind a shade layer anyway.
 */
export const BACKDROP_HERO_WIDTH = 1280;
/** Cast/crew portrait thumbnails (~120 CSS-px, ~154 on UHD chrome scale). */
export const PROFILE_WIDTH = 200;
/** Title logos on detail hero. */
export const LOGO_WIDTH = 500;

function pathExtension(pathname: string): string {
  const base = pathname.split("/").pop() ?? "";
  const dot = base.lastIndexOf(".");
  if (dot < 0) return "";
  return base.slice(dot);
}

/**
 * True when rewriting the path would invalidate a signature we cannot reproduce.
 *
 * Third-party signatures (S3 SigV4, GCS, Cloudflare) cover the exact object
 * path, so any rewrite breaks them and the URL must be used verbatim.
 *
 * Prairie's own artwork signature is excluded: it covers the artwork *revision*,
 * not the exact key, so selecting another width rung of the same image still
 * validates. Until the server made that change this guard matched Prairie's
 * `sig=` too, which meant the width constants in this file did nothing against a
 * real server and every TV rendered whichever rung the server picked.
 */
export function isSignedArtworkURL(objectPath: string): boolean {
  if (isPrairieSignedArtworkURL(objectPath)) return false;
  // AWS SigV4, GCS, generic Signature, and Cloudflare WAF token (?verify=).
  return /[?&](X-Amz-Signature|X-Goog-Signature|Signature|sig|verify)=/i.test(objectPath);
}

/**
 * True for a URL signed by the connected Prairie server's artwork store.
 *
 * Identified by the pair of query params it always emits together plus the
 * `/artwork/` path prefix it serves from — deliberately narrow, so a
 * third-party URL that happens to carry a `sig=` param is not mistaken for ours
 * and rewritten into a 403.
 */
export function isPrairieSignedArtworkURL(objectPath: string): boolean {
  if (!/[?&]sig=/.test(objectPath) || !/[?&]expires=/.test(objectPath)) return false;
  const withoutQuery = objectPath.split("?")[0] ?? "";
  return withoutQuery.includes("/artwork/");
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
