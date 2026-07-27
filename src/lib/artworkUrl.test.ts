import { beforeEach, describe, expect, it } from "vitest";
import {
  artworkCandidates,
  artworkSized,
  artworkSizedCandidates,
  artworkWidthVariant,
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
    localStorage.setItem("prairie.imageFormats", "webp,avif,png");
  });

  it("orders WebP → AVIF → PNG for WebP artwork", () => {
    expect(artworkCandidates("/art/original.rev.webp")).toEqual([
      "/art/original.rev.webp",
      "/art/original.rev.avif",
      "/art/original.rev.png",
    ]);
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

  it("tries the width variant first, then the canonical ladder", () => {
    // A width rung the server never generated must not dead-end on siblings
    // of a missing object — the original has to remain reachable.
    expect(artworkSizedCandidates("/art/original.rev.webp", 300)).toEqual([
      "/art/w300.rev.webp",
      "/art/w300.rev.png",
      "/art/original.rev.webp",
      "/art/original.rev.png",
    ]);
  });

  it("falls back to the plain ladder when no rewrite applies", () => {
    expect(artworkSizedCandidates("/art/cover.jpg", 300)).toEqual(["/art/cover.jpg"]);
    expect(artworkSizedCandidates("/art/original.rev.webp", null)).toEqual([
      "/art/original.rev.webp",
      "/art/original.rev.png",
    ]);
    expect(artworkSizedCandidates("", 300)).toEqual([]);
    expect(artworkSizedCandidates(null, 300)).toEqual([]);
  });
});
