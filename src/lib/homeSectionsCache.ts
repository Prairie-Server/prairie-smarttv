/**
 * Last-known Home rows, persisted so a cold launch can paint real content while
 * the request is still in flight. On TV hardware the network stack plus a cold
 * server query is the bulk of the wait, and rows rarely change between launches.
 *
 * Cached rows are trimmed: only the fields the cards read are stored, and only
 * enough items to fill the visible window, so the payload stays small enough to
 * parse cheaply on a weak SoC.
 */

import type { HomeSection } from "../api/home";

const STORAGE_KEY = "prairie.home.sections";
const CACHE_VERSION = 1;
/** Rows are re-fetched every launch; the cache only seeds the first paint. */
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_SECTIONS = 6;
const MAX_ITEMS_PER_SECTION = 12;

interface CachedPayload {
  version: number;
  savedAt: number;
  serverUrl: string;
  profileId: string;
  sections: HomeSection[];
}

function scopeMatches(payload: CachedPayload, serverUrl: string, profileId: string): boolean {
  return payload.serverUrl === serverUrl && payload.profileId === profileId;
}

function trim(sections: HomeSection[]): HomeSection[] {
  return sections.slice(0, MAX_SECTIONS).map((section) => ({
    ...section,
    items: section.items.slice(0, MAX_ITEMS_PER_SECTION).map((item) => ({
      content_id: item.content_id,
      type: item.type,
      title: item.title,
      year: item.year,
      poster_url: item.poster_url,
      backdrop_url: item.backdrop_url,
      series_title: item.series_title,
      season_number: item.season_number,
      episode_number: item.episode_number,
      position_seconds: item.position_seconds,
      duration_seconds: item.duration_seconds,
      user_state: item.user_state,
    })),
  }));
}

export function loadCachedHomeSections(
  serverUrl: string,
  profileId: string,
  storage: Pick<Storage, "getItem" | "removeItem"> = localStorage,
): HomeSection[] | null {
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as CachedPayload;
    if (parsed.version !== CACHE_VERSION) return null;
    if (!Array.isArray(parsed.sections) || parsed.sections.length === 0) return null;
    if (!scopeMatches(parsed, serverUrl, profileId)) return null;
    if (!Number.isFinite(parsed.savedAt) || Date.now() - parsed.savedAt > MAX_AGE_MS) return null;
    return parsed.sections;
  } catch {
    return null;
  }
}

export function saveCachedHomeSections(
  sections: HomeSection[],
  serverUrl: string,
  profileId: string,
  storage: Pick<Storage, "setItem" | "removeItem"> = localStorage,
): void {
  try {
    if (sections.length === 0) {
      storage.removeItem(STORAGE_KEY);
      return;
    }
    const payload: CachedPayload = {
      version: CACHE_VERSION,
      savedAt: Date.now(),
      serverUrl,
      profileId,
      sections: trim(sections),
    };
    storage.setItem(STORAGE_KEY, JSON.stringify(payload));
  } catch {
    // Quota or serialization failure is not worth surfacing.
  }
}

export function clearCachedHomeSections(storage: Pick<Storage, "removeItem"> = localStorage): void {
  try {
    storage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}
