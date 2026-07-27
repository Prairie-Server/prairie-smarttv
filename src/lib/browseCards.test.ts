import { describe, expect, it } from "vitest";
import {
  catalogItemProgress,
  catalogItemSubtitle,
  isContinueStyleSection,
  libraryTypeLabel,
  usesLandscapeCards,
} from "./browseCards";

describe("browseCards", () => {
  it("builds episode-aware subtitles", () => {
    expect(
      catalogItemSubtitle({
        content_id: "1",
        type: "episode",
        title: "Pilot",
        series_title: "Lost",
        season_number: 1,
        episode_number: 1,
      }),
    ).toBe("Lost · S1E1");
    expect(
      catalogItemSubtitle({
        content_id: "2",
        type: "movie",
        title: "Dune",
        year: 2021,
        rating_imdb: 8.1,
      }),
    ).toBe("2021 · ★ 8.1");
    expect(
      catalogItemSubtitle({
        content_id: "3",
        type: "movie",
        title: "Untitled",
      }),
    ).toBe("movie");
    expect(
      catalogItemSubtitle({
        content_id: "4",
        type: "",
        title: "Blank",
      }),
    ).toBeNull();
  });

  it("computes progress ratios", () => {
    expect(
      catalogItemProgress({
        content_id: "1",
        type: "movie",
        title: "A",
        position_seconds: 30,
        duration_seconds: 100,
      }),
    ).toBe(0.3);
    expect(
      catalogItemProgress({
        content_id: "1",
        type: "movie",
        title: "A",
        position_seconds: 30,
        duration_seconds: 0,
      }),
    ).toBeNull();
  });

  it("classifies continue-style sections and landscape usage", () => {
    expect(isContinueStyleSection("continue_watching")).toBe(true);
    expect(isContinueStyleSection("next_up")).toBe(true);
    expect(isContinueStyleSection("on_deck")).toBe(true);
    expect(isContinueStyleSection("recently_added")).toBe(false);
    expect(isContinueStyleSection(undefined)).toBe(false);
    expect(
      usesLandscapeCards("continue_watching", [{ content_id: "1", type: "episode", title: "Ep" }]),
    ).toBe(true);
    expect(
      usesLandscapeCards("continue_watching", [{ content_id: "1", type: "movie", title: "Film" }]),
    ).toBe(false);
    expect(
      usesLandscapeCards("recently_added", [{ content_id: "1", type: "episode", title: "Ep" }]),
    ).toBe(false);
  });

  it("labels library types", () => {
    expect(libraryTypeLabel("series")).toBe("TV Shows");
    expect(libraryTypeLabel("movies")).toBe("Movies");
    expect(libraryTypeLabel("audiobooks")).toBe("Audiobooks");
    expect(libraryTypeLabel("ebooks")).toBe("Ebooks");
    expect(libraryTypeLabel("manga")).toBe("Manga");
    expect(libraryTypeLabel("mixed")).toBe("Mixed");
    expect(libraryTypeLabel("custom")).toBe("Custom");
    expect(libraryTypeLabel(null)).toBe("Library");
  });
});
