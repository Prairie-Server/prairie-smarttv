import type { CatalogItem } from "../api/catalog";

export function catalogItemSubtitle(item: CatalogItem): string | null {
  if (item.series_title && item.season_number != null && item.episode_number != null) {
    return `${item.series_title} · S${item.season_number}E${item.episode_number}`;
  }
  const bits: string[] = [];
  if (item.year) bits.push(String(item.year));
  if (item.rating_imdb != null) bits.push(`★ ${item.rating_imdb.toFixed(1)}`);
  if (bits.length) return bits.join(" · ");
  if (item.type) return item.type;
  return null;
}

export function catalogItemProgress(item: CatalogItem): number | null {
  const pos = item.position_seconds;
  const dur = item.duration_seconds;
  if (pos == null || dur == null || dur <= 0) return null;
  return Math.min(1, Math.max(0, pos / dur));
}

export function isContinueStyleSection(sectionType: string | undefined): boolean {
  if (!sectionType) return false;
  const t = sectionType.toLowerCase();
  return t === "continue_watching" || t === "next_up" || t === "on_deck";
}

export function usesLandscapeCards(sectionType: string | undefined, items: CatalogItem[]): boolean {
  if (!isContinueStyleSection(sectionType)) return false;
  return items.some((item) => item.type === "episode");
}

export function libraryTypeLabel(type: string | undefined | null): string {
  switch ((type ?? "").toLowerCase()) {
    case "movie":
    case "movies":
      return "Movies";
    case "series":
    case "show":
    case "tv":
      return "TV Shows";
    case "audiobook":
    case "audiobooks":
      return "Audiobooks";
    case "ebook":
    case "ebooks":
      return "Ebooks";
    case "manga":
      return "Manga";
    case "mixed":
      return "Mixed";
    default:
      return type ? type.charAt(0).toUpperCase() + type.slice(1) : "Library";
  }
}

export type CatalogSortOption = {
  value: string;
  label: string;
  order: "asc" | "desc";
};

export const LIBRARY_SORT_OPTIONS: CatalogSortOption[] = [
  { value: "title", label: "Title", order: "asc" },
  { value: "date_added", label: "Date Added", order: "desc" },
  { value: "release_date", label: "Release Date", order: "desc" },
  { value: "year", label: "Year", order: "desc" },
  { value: "rating_imdb", label: "IMDb Rating", order: "desc" },
];
