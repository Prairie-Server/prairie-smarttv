import { describe, expect, it } from "vitest";
import { ARTWORK_ROLE_WIDTH, artworkRoleWidth } from "./artworkRole";
import {
  BACKDROP_CARD_WIDTH,
  BACKDROP_HERO_WIDTH,
  LOGO_WIDTH,
  POSTER_WIDTH,
  PROFILE_WIDTH,
  STILL_WIDTH,
} from "./artworkUrl";

/**
 * The server ladder, mirrored from internal/artworkkey.VariantWidths.
 *
 * Since the client began rewriting rungs for real (#81), asking for a width the
 * server never generates is no longer harmless-but-inert: it takes the
 * next-widest rung through the fallback, quietly costing more bytes than the
 * constant claims to save.
 */
const SERVER_LADDER = {
  poster: [500, 300, 200],
  profile: [500, 300, 200],
  // w200 retired: an episode still renders ~358 px on a UHD panel, so w200
  // would upscale, and nothing on any client ever requested one.
  still: [500, 300],
  backdrop: [1920, 1280, 300],
  logo: [500],
} as const;

describe("artwork width ladder", () => {
  it("keeps every width constant on a rung the server generates", () => {
    expect(SERVER_LADDER.poster).toContain(POSTER_WIDTH);
    expect(SERVER_LADDER.profile).toContain(PROFILE_WIDTH);
    expect(SERVER_LADDER.still).toContain(STILL_WIDTH);
    expect(SERVER_LADDER.backdrop).toContain(BACKDROP_CARD_WIDTH);
    expect(SERVER_LADDER.backdrop).toContain(BACKDROP_HERO_WIDTH);
    expect(SERVER_LADDER.logo).toContain(LOGO_WIDTH);
  });

  it("never asks for the retired w200 still", () => {
    expect(STILL_WIDTH).not.toBe(200);
    expect(artworkRoleWidth("still")).not.toBe(200);
  });

  it("keeps poster-shaped roles on the poster rung", () => {
    // Both are documented as poster-shaped and never larger than a card, so
    // they ride the poster ladder rather than one of their own.
    expect(ARTWORK_ROLE_WIDTH.libraryTile).toBe(POSTER_WIDTH);
    expect(ARTWORK_ROLE_WIDTH.channel).toBe(POSTER_WIDTH);
  });

  it("resolves a width for every role", () => {
    for (const [role, width] of Object.entries(ARTWORK_ROLE_WIDTH)) {
      expect(width, `${role} has no width`).toBeGreaterThan(0);
      // Any role must land on some rung the server generates, whichever image
      // type backs it — otherwise the request falls back to a wider object.
      const everyRung = Object.values(SERVER_LADDER).flat() as number[];
      expect(everyRung, `${role} width ${width} is not a server rung`).toContain(width);
    }
  });
});
