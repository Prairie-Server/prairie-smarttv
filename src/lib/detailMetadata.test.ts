import { describe, expect, it } from "vitest";
import {
  crewLine,
  episodeProgressRatio,
  formatAirDate,
  formatResumeLabel,
  formatRuntimeMinutes,
  formatRuntimeSeconds,
  hasResumeProgress,
  isSeriesType,
  movieFacts,
  pickNextUpEpisode,
  resumePositionSeconds,
  seriesFacts,
  seriesYearLabel,
  sourceTokens,
  starringText,
  typeLabel,
} from "./detailMetadata";
import type { EpisodeSummary, ItemDetail } from "../api/catalog";

function movie(overrides: Partial<ItemDetail> = {}): ItemDetail {
  return {
    content_id: "m1",
    type: "movie",
    title: "Dune",
    year: 2021,
    runtime: 155,
    rating_imdb: 8.1,
    versions: [
      {
        file_id: 1,
        resolution: "3840x2160",
        hdr: true,
        audio_tracks: [{ layout: "5.1", channels: 6, default: true }],
        subtitle_tracks: [{ language: "en" }],
      },
    ],
    cast: [{ name: "Timothee Chalamet" }, { name: "Zendaya" }, { name: "Rebecca Ferguson" }],
    crew: [
      { name: "Denis Villeneuve", job: "Director" },
      { name: "Jon Spaihts", job: "Writer" },
    ],
    genres: ["Sci-Fi", "Adventure", "Drama"],
    ...overrides,
  };
}

describe("detailMetadata", () => {
  it("labels types and series detection", () => {
    expect(typeLabel("movie")).toBe("Movie");
    expect(typeLabel("series")).toBe("TV Show");
    expect(typeLabel("show")).toBe("TV Show");
    expect(typeLabel("episode")).toBe("Episode");
    expect(typeLabel("season")).toBe("Season");
    expect(typeLabel("podcast")).toBe("Podcast");
    expect(isSeriesType("series")).toBe(true);
    expect(isSeriesType("tv")).toBe(true);
    expect(isSeriesType("movie")).toBe(false);
    expect(isSeriesType(null)).toBe(false);
  });

  it("formats runtimes", () => {
    expect(formatRuntimeMinutes(45)).toBe("45m");
    expect(formatRuntimeMinutes(60)).toBe("1h");
    expect(formatRuntimeMinutes(155)).toBe("2h 35m");
    expect(formatRuntimeMinutes(0)).toBeNull();
    expect(formatRuntimeSeconds(3660)).toBe("1h 1m");
    expect(formatRuntimeSeconds(null)).toBeNull();
  });

  it("builds movie facts with quality chips", () => {
    const facts = movieFacts(movie());
    expect(facts).toEqual(
      expect.arrayContaining([
        { kind: "text", value: "2021" },
        { kind: "text", value: "2h 35m" },
        { kind: "score", value: "8.1" },
        { kind: "chip", value: "4K" },
        { kind: "chip", value: "HDR" },
        { kind: "chip", value: "5.1" },
        { kind: "chip", value: "CC" },
      ]),
    );
  });

  it("prefers last played version for quality chips", () => {
    const facts = movieFacts(
      movie({
        user_data: { last_file_id: 2 },
        versions: [
          { file_id: 1, resolution: "1920x1080" },
          {
            file_id: 2,
            resolution: "1280x720",
            audio_tracks: [{ layout: "atmos", default: true }],
          },
        ],
      }),
    );
    expect(facts).toEqual(
      expect.arrayContaining([
        { kind: "chip", value: "HD" },
        { kind: "chip", value: "ATMOS" },
      ]),
    );
  });

  it("maps channel counts and codec atmos fallbacks", () => {
    expect(
      movieFacts(
        movie({
          versions: [{ file_id: 1, resolution: "480p", audio_tracks: [{ channels: 8 }] }],
        }),
      ),
    ).toEqual(
      expect.arrayContaining([
        { kind: "chip", value: "SD" },
        { kind: "chip", value: "7.1" },
      ]),
    );
    expect(
      movieFacts(
        movie({
          versions: [{ file_id: 1, codec_audio: "truehd atmos" }],
        }),
      ),
    ).toEqual(expect.arrayContaining([{ kind: "chip", value: "ATMOS" }]));
  });

  it("builds series year range and season count", () => {
    const facts = seriesFacts(
      movie({
        type: "series",
        first_air_date: "2019-01-01",
        last_air_date: "2023-01-01",
        season_count: 4,
        episode_count: 40,
      }),
      4,
    );
    expect(facts).toEqual(
      expect.arrayContaining([
        { kind: "text", value: "2019–2023" },
        { kind: "text", value: "4 Seasons" },
        { kind: "text", value: "40 Episodes" },
      ]),
    );
    expect(seriesYearLabel(movie({ year: 2020, first_air_date: null, last_air_date: null }))).toBe(
      "2020",
    );
    expect(seriesYearLabel(movie({ year: null, first_air_date: "2021-05-01" }))).toBe("2021");
  });

  it("builds source, starring, and crew lines", () => {
    expect(sourceTokens(movie())).toEqual(["Movie", "Sci-Fi", "Adventure"]);
    expect(sourceTokens(movie({ type: "series", genres: ["Drama"] }))).toEqual([
      "TV Show",
      "Drama",
    ]);
    expect(starringText(movie())).toBe("Starring Timothee Chalamet, Zendaya, Rebecca Ferguson");
    expect(starringText(movie({ cast: [] }))).toBeNull();
    expect(crewLine(movie())).toBe("Directed by Denis Villeneuve");
    expect(crewLine(movie({ type: "series", crew: [{ name: "Creator", job: "Creator" }] }))).toBe(
      "Created by Creator",
    );
    expect(crewLine(movie({ crew: [{ name: "Editor", job: "Editor" }] }))).toBeNull();
  });

  it("detects resume progress and formats label", () => {
    expect(hasResumeProgress(120, 3600)).toBe(true);
    expect(hasResumeProgress(10, 3600)).toBe(false);
    expect(hasResumeProgress(10, 3600, true)).toBe(true);
    expect(resumePositionSeconds(100, 1000)).toBe(100);
    expect(resumePositionSeconds(990, 1000)).toBeUndefined();
    expect(formatResumeLabel(3723)).toBe("Resume 1:02:03");
    expect(formatResumeLabel(125)).toBe("Resume 2:05");
  });

  it("picks next-up episode preferencing in-progress then unwatched", () => {
    const episodes: EpisodeSummary[] = [
      { content_id: "e1", title: "One", episode_number: 1, user_data: { played: true } },
      {
        content_id: "e2",
        title: "Two",
        episode_number: 2,
        user_data: { played: false, is_in_progress: true, position_seconds: 40 },
      },
      { content_id: "e3", title: "Three", episode_number: 3, user_data: { played: false } },
    ];
    expect(pickNextUpEpisode(episodes)?.content_id).toBe("e2");
    expect(
      pickNextUpEpisode([
        { content_id: "e1", title: "One", user_data: { played: true } },
        { content_id: "e3", title: "Three", user_data: { played: false } },
      ])?.content_id,
    ).toBe("e3");
    expect(pickNextUpEpisode([])).toBeNull();
  });

  it("computes episode progress and formats air dates", () => {
    expect(
      episodeProgressRatio({
        content_id: "e1",
        title: "One",
        user_data: { position_seconds: 300, duration_seconds: 1000 },
      }),
    ).toBe(0.3);
    expect(
      episodeProgressRatio({
        content_id: "e1",
        title: "One",
        runtime: 40,
        user_data: { position_seconds: 600 },
      }),
    ).toBe(0.25);
    expect(
      episodeProgressRatio({
        content_id: "e1",
        title: "One",
        user_data: { position_seconds: 10, duration_seconds: 1000 },
      }),
    ).toBeNull();
    expect(formatAirDate("2021-10-22")).toMatch(/2021/);
    expect(formatAirDate(null)).toBeNull();
    expect(formatAirDate("not-a-date")).toBe("not-a-date");
  });
});
