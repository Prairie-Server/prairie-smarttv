/**
 * Artwork URL helpers mirroring prairie-server web/src/lib/artworkUrl.ts.
 * Canonical cache keys stay .webp; clients pick the best sibling immediately
 * using one-time decode capability detection (see imageFormats.ts).
 *
 * Path rewriting is skipped for SigV4-style signed URLs (rewriting the path
 * would invalidate the signature).
 */

import { getImageFormats, orderRasterCandidates } from "./imageFormats";

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

/** Best immediate artwork URL without trial-and-error format probing. */
export function artworkPreferred(objectPath: string | null | undefined): string {
  return artworkCandidates(objectPath)[0] ?? "";
}
