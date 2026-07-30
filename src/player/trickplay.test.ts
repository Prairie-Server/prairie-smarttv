import { describe, expect, it } from "vitest";
import { prefetchTrickplaySheets, resolveTrickplayTile, type TrickplayInfo } from "./trickplay";

function sampleTrickplay(overrides: Partial<TrickplayInfo> = {}): TrickplayInfo {
  return {
    interval_seconds: 10,
    width: 320,
    height: 180,
    tile_columns: 10,
    tile_rows: 10,
    thumbnail_count: 150,
    sheets: [
      { index: 0, url: "https://cdn.example/sheet-0.webp" },
      { index: 1, url: "https://cdn.example/sheet-1.webp" },
    ],
    ...overrides,
  };
}

describe("resolveTrickplayTile", () => {
  it("returns null when trickplay is missing or empty", () => {
    expect(resolveTrickplayTile(null, 12)).toBeNull();
    expect(resolveTrickplayTile(sampleTrickplay({ thumbnail_count: 0 }), 12)).toBeNull();
    expect(resolveTrickplayTile(sampleTrickplay({ sheets: [] }), 12)).toBeNull();
  });

  it("maps time onto the correct sheet crop", () => {
    // 125s → tile 12 → sheet 0, col 2, row 1
    const early = resolveTrickplayTile(sampleTrickplay(), 125);
    expect(early).toEqual({
      url: "https://cdn.example/sheet-0.webp",
      width: 320,
      height: 180,
      backgroundPosition: `${(2 / 9) * 100}% ${(1 / 9) * 100}%`,
      backgroundSize: "1000% 1000%",
    });

    // 1050s → tile 105 → sheet 1, col 5, row 0
    const later = resolveTrickplayTile(sampleTrickplay(), 1050);
    expect(later).toEqual({
      url: "https://cdn.example/sheet-1.webp",
      width: 320,
      height: 180,
      backgroundPosition: `${(5 / 9) * 100}% 0%`,
      backgroundSize: "1000% 1000%",
    });
  });

  it("clamps past the last thumbnail", () => {
    const tile = resolveTrickplayTile(sampleTrickplay(), 99999);
    expect(tile?.url).toBe("https://cdn.example/sheet-1.webp");
    // last tile index 149 → local 49 → col 9, row 4
    expect(tile?.backgroundPosition).toBe(`100% ${(4 / 9) * 100}%`);
  });
});

describe("prefetchTrickplaySheets", () => {
  it("does not throw without Image", () => {
    expect(() => prefetchTrickplaySheets(sampleTrickplay(), 0)).not.toThrow();
  });
});
