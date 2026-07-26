import { describe, expect, it } from "vitest";
import { artworkCandidates, webPAVIFSibling, webPPNGSibling } from "./artworkUrl";

describe("webPAVIFSibling", () => {
  it("rewrites WebP object keys to AVIF siblings", () => {
    expect(webPAVIFSibling("library/1/poster/original.abc123.webp")).toBe(
      "library/1/poster/original.abc123.avif",
    );
    expect(webPAVIFSibling("original.webp")).toBe("original.avif");
  });

  it("preserves query strings on absolute URLs", () => {
    expect(
      webPAVIFSibling("https://cdn.example.com/art/original.rev.webp?X-Amz-Signature=abc"),
    ).toBe("https://cdn.example.com/art/original.rev.avif?X-Amz-Signature=abc");
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

  it("preserves query strings", () => {
    expect(webPPNGSibling("https://cdn.example.com/art/original.webp?sig=1")).toBe(
      "https://cdn.example.com/art/original.png?sig=1",
    );
  });
});

describe("artworkCandidates", () => {
  it("orders AVIF → WebP → PNG for WebP artwork", () => {
    expect(artworkCandidates("/art/original.rev.webp")).toEqual([
      "/art/original.rev.avif",
      "/art/original.rev.webp",
      "/art/original.rev.png",
    ]);
  });

  it("returns the original URL alone when it is not WebP", () => {
    expect(artworkCandidates("/art/cover.jpg")).toEqual(["/art/cover.jpg"]);
  });
});
