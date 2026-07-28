import { describe, expect, it } from "vitest";
import { artworkSized, artworkWidthVariant, isSignedOriginalArtworkURL } from "./artworkUrl";

const SIGNED_ORIGINAL = "/artwork/lib/1/poster/original.7.webp?sig=abc&expires=99";
const SIGNED_RUNG = "/artwork/lib/1/poster/w500.7.webp?sig=abc&expires=99";

/**
 * The server signs `original` against exactly itself, so rewriting its width is
 * a 403 — which on a television is a blank card with no console to explain it.
 * This took out cast portraits in the browser first.
 */
describe("signed original artwork URLs", () => {
  it("refuses to rewrite the width of a signed original", () => {
    expect(isSignedOriginalArtworkURL(SIGNED_ORIGINAL)).toBe(true);
    expect(artworkWidthVariant(SIGNED_ORIGINAL, 200)).toBe("");
  });

  it("falls back to the untouched URL so the art still renders", () => {
    expect(artworkSized(SIGNED_ORIGINAL, 200)).toBe(SIGNED_ORIGINAL);
  });

  it("still rewrites a signed sized rung, which shares the revision scope", () => {
    expect(isSignedOriginalArtworkURL(SIGNED_RUNG)).toBe(false);
    expect(artworkWidthVariant(SIGNED_RUNG, 200)).toContain("/w200.7.webp");
  });

  it("leaves unsigned originals rewritable for local dev and tests", () => {
    const unsigned = "/artwork/lib/1/poster/original.7.webp";
    expect(isSignedOriginalArtworkURL(unsigned)).toBe(false);
    expect(artworkWidthVariant(unsigned, 200)).toContain("/w200.7.webp");
  });

  it("does not mistake a third-party URL containing 'original' for ours", () => {
    expect(
      isSignedOriginalArtworkURL("https://cdn.example.test/original.jpg?sig=a&expires=1"),
    ).toBe(false);
  });
});
