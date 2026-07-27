import { beforeEach, describe, expect, it } from "vitest";
import type { HomeSection } from "../api/home";
import {
  clearCachedHomeSections,
  loadCachedHomeSections,
  saveCachedHomeSections,
} from "./homeSectionsCache";

const SERVER = "https://tv.example.com";
const PROFILE = "p1";

function section(id: string, itemCount: number): HomeSection {
  return {
    id,
    title: `Row ${id}`,
    section_type: "recent",
    items: Array.from({ length: itemCount }, (_, index) => ({
      content_id: `${id}-${index}`,
      type: "movie",
      title: `Item ${index}`,
      poster_url: "/artwork/library/1/poster/original.rev.webp",
    })),
  } as HomeSection;
}

beforeEach(() => {
  localStorage.clear();
});

describe("homeSectionsCache", () => {
  it("round-trips rows for the same server and profile", () => {
    saveCachedHomeSections([section("a", 3)], SERVER, PROFILE);
    const loaded = loadCachedHomeSections(SERVER, PROFILE);
    expect(loaded).toHaveLength(1);
    expect(loaded?.[0]?.items).toHaveLength(3);
    expect(loaded?.[0]?.items[0]?.title).toBe("Item 0");
  });

  it("trims rows and items so the payload stays cheap to parse", () => {
    saveCachedHomeSections(
      Array.from({ length: 10 }, (_, index) => section(`s${index}`, 40)),
      SERVER,
      PROFILE,
    );
    const loaded = loadCachedHomeSections(SERVER, PROFILE);
    expect(loaded?.length).toBe(6);
    expect(loaded?.[0]?.items.length).toBe(12);
  });

  it("ignores cache from another server or profile", () => {
    saveCachedHomeSections([section("a", 2)], SERVER, PROFILE);
    expect(loadCachedHomeSections("https://other.example.com", PROFILE)).toBeNull();
    expect(loadCachedHomeSections(SERVER, "p2")).toBeNull();
  });

  it("ignores stale, empty, and malformed entries", () => {
    saveCachedHomeSections([section("a", 2)], SERVER, PROFILE);
    const raw = JSON.parse(localStorage.getItem("prairie.home.sections") ?? "{}") as {
      savedAt: number;
    };
    raw.savedAt = Date.now() - 48 * 60 * 60 * 1000;
    localStorage.setItem("prairie.home.sections", JSON.stringify(raw));
    expect(loadCachedHomeSections(SERVER, PROFILE)).toBeNull();

    localStorage.setItem("prairie.home.sections", "not json");
    expect(loadCachedHomeSections(SERVER, PROFILE)).toBeNull();

    localStorage.setItem("prairie.home.sections", JSON.stringify({ version: 99, sections: [] }));
    expect(loadCachedHomeSections(SERVER, PROFILE)).toBeNull();
  });

  it("clears the entry when there is nothing to cache", () => {
    saveCachedHomeSections([section("a", 2)], SERVER, PROFILE);
    saveCachedHomeSections([], SERVER, PROFILE);
    expect(loadCachedHomeSections(SERVER, PROFILE)).toBeNull();

    saveCachedHomeSections([section("a", 2)], SERVER, PROFILE);
    clearCachedHomeSections();
    expect(loadCachedHomeSections(SERVER, PROFILE)).toBeNull();
  });
});
