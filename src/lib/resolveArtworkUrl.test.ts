import { describe, expect, it } from "vitest";
import { joinServerUrl, resolveArtworkUrl } from "./resolveArtworkUrl";

describe("resolveArtworkUrl", () => {
  it("joins relative artwork paths to the Prairie origin", () => {
    expect(
      resolveArtworkUrl(
        "/artwork/library/1/poster/original.webp?expires=1&sig=abc",
        "https://prairie.example",
      ),
    ).toBe("https://prairie.example/artwork/library/1/poster/original.webp?expires=1&sig=abc");
  });

  it("leaves absolute URLs alone", () => {
    expect(resolveArtworkUrl("https://cdn.example/art.webp", "https://prairie.example")).toBe(
      "https://cdn.example/art.webp",
    );
  });

  it("returns the path unchanged without a server url", () => {
    expect(resolveArtworkUrl("/artwork/x.webp", "")).toBe("/artwork/x.webp");
  });
});

describe("joinServerUrl", () => {
  it("handles protocol-relative URLs", () => {
    expect(joinServerUrl("https://prairie.example", "//cdn.example/a.webp")).toBe(
      "https://cdn.example/a.webp",
    );
  });
});
