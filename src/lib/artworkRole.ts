/**
 * What an artwork image *is*, rather than how wide someone remembered to make it.
 *
 * Every call site used to pass a raw `widthHint`, and forgetting it silently
 * fell back to the `original` object — a multi-megabyte source image on a TV.
 * Two screens shipped that way (Libraries, and the Live TV row on Home). A role
 * is required instead, so the ladder rung, the preview rung and the decode
 * behaviour for each kind of artwork are decided in exactly one place.
 *
 * Width rungs must exist in the server ladder (internal/artworkkey.VariantWidths):
 *   poster / still / profile -> w500, w300
 *   backdrop                 -> w1920, w1280, w300
 *   logo                     -> w500
 */

import {
  BACKDROP_CARD_WIDTH,
  BACKDROP_HERO_WIDTH,
  LOGO_WIDTH,
  POSTER_WIDTH,
  PROFILE_WIDTH,
  STILL_WIDTH,
} from "./artworkUrl";

export type ArtworkRole =
  /** Poster card in a rail or grid. */
  | "poster"
  /** Landscape card fed by a backdrop. */
  | "backdropCard"
  /** Full-bleed hero backdrop (Home and detail). */
  | "backdropHero"
  /** Title logo on the detail hero. */
  | "logo"
  /** Episode still. */
  | "still"
  /** Cast/crew portrait, and profile avatars. */
  | "portrait"
  /** Library tile art. */
  | "libraryTile"
  /** Live TV channel / programme art. */
  | "channel";

export const ARTWORK_ROLE_WIDTH: Record<ArtworkRole, number> = {
  poster: POSTER_WIDTH,
  backdropCard: BACKDROP_CARD_WIDTH,
  backdropHero: BACKDROP_HERO_WIDTH,
  logo: LOGO_WIDTH,
  still: STILL_WIDTH,
  portrait: PROFILE_WIDTH,
  // Library tiles are poster-shaped and never larger than a card.
  libraryTile: POSTER_WIDTH,
  channel: POSTER_WIDTH,
};

/**
 * Roles big enough that a cheap rung should paint first.
 *
 * Only hero backdrops qualify: at 1280×720 they cost ~3.7 MB to decode, which is
 * long enough on TV hardware to stall the remote. Everything else decodes fast
 * enough that a second request would cost more than it saves.
 */
export const ARTWORK_PREVIEW_ROLE: Partial<Record<ArtworkRole, ArtworkRole>> = {
  backdropHero: "backdropCard",
};

export function artworkRoleWidth(role: ArtworkRole): number {
  return ARTWORK_ROLE_WIDTH[role];
}

export function artworkPreviewWidth(role: ArtworkRole): number | null {
  const preview = ARTWORK_PREVIEW_ROLE[role];
  return preview ? ARTWORK_ROLE_WIDTH[preview] : null;
}
