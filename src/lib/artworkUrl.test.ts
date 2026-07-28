import { beforeEach, describe, expect, it } from "vitest";
import {
  artworkCandidates,
  artworkPreferred,
  artworkSized,
  artworkSizedCandidates,
  artworkWidthVariant,
  isPrairieSignedArtworkURL,
  isSignedArtworkURL,
  webPAVIFSibling,
  webPPNGSibling,
} from "./artworkUrl";
import { resetImageFormatsCacheForTests } from "./imageFormats";

describe("webPAVIFSibling", () => {
  it("rewrites WebP object keys to AVIF siblings", () => {
    expect(webPAVIFSibling("library/1/poster/original.abc123.webp")).toBe(
      "library/1/poster/original.abc123.avif",
    );
    expect(webPAVIFSibling("original.webp")).toBe("original.avif");
  });

  it("does not rewrite signed absolute URLs", () => {
    expect(
      webPAVIFSibling("https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"),
    ).toBe("");
  });

  it("returns empty for non-WebP inputs", () => {
    expect(webPAVIFSibling("poster.jpg")).toBe("");
    expect(webPAVIFSibling("https://cdn.example.com/art/original.png")).toBe("");
    expect(webPAVIFSibling("")).toBe("");
    expect(webPAVIFSibling(null)).toBe("");
  });
});

describe("webPPNGSibling", () => {
  it("rewrites WebP object keys to PNG siblings", () => {
    expect(webPPNGSibling("library/1/poster/original.abc123.webp")).toBe(
      "library/1/poster/original.abc123.png",
    );
  });

  it("does not rewrite signed URLs", () => {
    expect(webPPNGSibling("https://cdn.example.com/art/original.webp?sig=1")).toBe("");
  });
});

describe("isSignedArtworkURL", () => {
  it("detects common signature query params", () => {
    expect(isSignedArtworkURL("https://x/?X-Amz-Signature=1")).toBe(true);
    expect(isSignedArtworkURL("https://x/?Signature=1")).toBe(true);
    expect(isSignedArtworkURL("https://x/?verify=token")).toBe(true);
    expect(isSignedArtworkURL("https://x/art.webp")).toBe(false);
  });

  // Prairie signs the artwork revision, not the exact key, so picking another
  // rung of the same image still validates. Treating it as unrewritable is what
  // made every width constant in this file inert against a real server.
  it("does not treat Prairie's own artwork signature as unrewritable", () => {
    const signed = "/artwork/library/1/poster/w500.rev.webp?expires=123&sig=abc";
    expect(isPrairieSignedArtworkURL(signed)).toBe(true);
    expect(isSignedArtworkURL(signed)).toBe(false);
  });

  it("only claims URLs that carry the store's full shape", () => {
    // sig= without expires=, and neither under /artwork/ — a third-party URL
    // that merely happens to use the same param name must stay untouched.
    expect(isPrairieSignedArtworkURL("https://cdn.example.com/art/w500.webp?sig=abc")).toBe(false);
    expect(isSignedArtworkURL("https://cdn.example.com/art/w500.webp?sig=abc")).toBe(true);
    expect(isPrairieSignedArtworkURL("/artwork/x/w500.rev.webp?expires=1")).toBe(false);
    expect(isPrairieSignedArtworkURL("https://x/?X-Amz-Signature=1&expires=1&sig=a")).toBe(false);
  });
});

describe("artworkWidthVariant", () => {
  it("rewrites original / wN path segments to the requested width", () => {
    expect(artworkWidthVariant("library/1/poster/original.abc.webp", 300)).toBe(
      "library/1/poster/w300.abc.webp",
    );
    expect(artworkWidthVariant("library/1/poster/w780.abc.webp", 300)).toBe(
      "library/1/poster/w300.abc.webp",
    );
    expect(artworkWidthVariant("https://cdn.example.com/art/original.rev.webp", 500)).toBe(
      "https://cdn.example.com/art/w500.rev.webp",
    );
  });

  // The signature has to travel with the rewritten URL or the request 403s.
  it("rewrites a Prairie-signed URL and keeps its query intact", () => {
    expect(
      artworkWidthVariant("/artwork/library/1/poster/w500.rev.webp?expires=123&sig=abc", 200),
    ).toBe("/artwork/library/1/poster/w200.rev.webp?expires=123&sig=abc");
    expect(
      artworkWidthVariant(
        "https://tv.example.com/artwork/library/1/poster/w500.rev.webp?expires=123&sig=abc",
        200,
      ),
    ).toBe("https://tv.example.com/artwork/library/1/poster/w200.rev.webp?expires=123&sig=abc");
  });

  it("returns empty for signed URLs, missing width segments, or bad input", () => {
    expect(
      artworkWidthVariant("https://cdn.example.com/art/original.webp?X-Amz-Signature=1", 300),
    ).toBe("");
    expect(artworkWidthVariant("poster.jpg", 300)).toBe("");
    expect(artworkWidthVariant("", 300)).toBe("");
    expect(artworkWidthVariant("library/1/poster/original.abc.webp", 0)).toBe("");
  });
});

describe("artworkSized", () => {
  it("prefers a width variant and falls back to the canonical URL", () => {
    expect(artworkSized("library/1/poster/original.abc.webp", 300)).toBe(
      "library/1/poster/w300.abc.webp",
    );
    expect(artworkSized("poster.jpg", 300)).toBe("poster.jpg");
    expect(artworkSized("library/1/poster/original.abc.webp", null)).toBe(
      "library/1/poster/original.abc.webp",
    );
    expect(artworkSized("", 300)).toBe("");
  });
});

describe("artworkCandidates", () => {
  beforeEach(() => {
    resetImageFormatsCacheForTests();
    localStorage.setItem("prairie.imageFormats", "avif,webp,png");
  });

  it("does not invent AVIF/PNG siblings from a WebP path", () => {
    expect(artworkCandidates("/art/original.rev.webp")).toEqual(["/art/original.rev.webp"]);
  });

  it("picks the single best among API-provided siblings", () => {
    expect(
      artworkPreferred("/art/original.rev.webp", {
        avif: "/art/original.rev.avif",
        png: "/art/original.rev.png",
      }),
    ).toBe("/art/original.rev.avif");
  });

  it("uses WebP when the client cannot decode AVIF even if AVIF is provided", () => {
    resetImageFormatsCacheForTests();
    localStorage.setItem("prairie.imageFormats", "webp,png");
    expect(
      artworkPreferred("/art/original.rev.webp", {
        avif: "/art/original.rev.avif",
      }),
    ).toBe("/art/original.rev.webp");
  });

  it("returns the original URL alone when it is not WebP", () => {
    expect(artworkCandidates("/art/cover.jpg")).toEqual(["/art/cover.jpg"]);
  });

  it("returns only the signed URL without inventing siblings", () => {
    const signed = "https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc";
    expect(artworkCandidates(signed)).toEqual([signed]);
  });
});

describe("artworkSizedCandidates", () => {
  beforeEach(() => {
    resetImageFormatsCacheForTests();
    localStorage.setItem("prairie.imageFormats", "webp,png");
  });

  it("tries the width variant then the same-format original — never a format cascade", () => {
    expect(artworkSizedCandidates("/art/original.rev.webp", 300)).toEqual([
      "/art/w300.rev.webp",
      "/art/original.rev.webp",
    ]);
  });

  it("applies width to the preferred API sibling", () => {
    resetImageFormatsCacheForTests();
    localStorage.setItem("prairie.imageFormats", "avif,webp,png");
    expect(
      artworkSizedCandidates("/art/original.rev.webp", 300, {
        avif: "/art/original.rev.avif",
      }),
    ).toEqual(["/art/w300.rev.avif", "/art/original.rev.avif"]);
  });

  it("falls back to the plain URL when no rewrite applies", () => {
    expect(artworkSizedCandidates("/art/cover.jpg", 300)).toEqual(["/art/cover.jpg"]);
    expect(artworkSizedCandidates("/art/original.rev.webp", null)).toEqual([
      "/art/original.rev.webp",
    ]);
    expect(artworkSizedCandidates("", 300)).toEqual([]);
    expect(artworkSizedCandidates(null, 300)).toEqual([]);
  });
});
