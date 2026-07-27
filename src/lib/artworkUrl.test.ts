import { beforeEach, describe, expect, it } from "vitest";
import {
  artworkCandidates,
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
