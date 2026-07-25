import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface CatalogItem {
  content_id: string;
  type: string;
  title: string;
  year?: number | null;
  poster_url?: string | null;
  backdrop_url?: string | null;
  overview?: string | null;
  series_id?: string | null;
  series_title?: string | null;
  season_number?: number | null;
  episode_number?: number | null;
  position_seconds?: number | null;
  duration_seconds?: number | null;
}

export interface CatalogResponse {
  total?: number;
  has_more?: boolean;
  snapshot?: string;
  items: CatalogItem[];
}

export interface CatalogQuery {
  libraryId?: number;
  type?: string;
  q?: string;
  source?: string;
  collectionId?: string;
  offset?: number;
  limit?: number;
  snapshot?: string;
  sort?: string;
  order?: string;
}

function buildCatalogPath(query: CatalogQuery): string {
  const params = new URLSearchParams();
  if (query.libraryId != null) params.set("library_id", String(query.libraryId));
  if (query.type) params.set("type", query.type);
  if (query.q) params.set("q", query.q);
  if (query.source) params.set("source", query.source);
  if (query.collectionId) params.set("collection_id", query.collectionId);
  if (query.offset != null) params.set("offset", String(query.offset));
  if (query.limit != null) params.set("limit", String(query.limit));
  if (query.snapshot) params.set("snapshot", query.snapshot);
  if (query.sort) params.set("sort", query.sort);
  if (query.order) params.set("order", query.order);
  const qs = params.toString();
  return qs ? `/api/v1/catalog?${qs}` : "/api/v1/catalog";
}

export async function fetchCatalog(
  session: PrairieSession,
  query: CatalogQuery = {},
  fetchImpl?: typeof fetch,
): Promise<CatalogResponse> {
  const data = await apiRequest<CatalogResponse>(
    sessionClient(session, fetchImpl),
    buildCatalogPath(query),
  );
  return {
    ...data,
    items: data.items ?? [],
  };
}

export interface ItemDetail extends CatalogItem {
  versions?: Array<{ file_id: number }>;
}

export async function fetchItemDetail(
  session: PrairieSession,
  contentId: string,
  fetchImpl?: typeof fetch,
): Promise<ItemDetail> {
  return apiRequest<ItemDetail>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/items/${encodeURIComponent(contentId)}`,
  );
}

export interface SeasonSummary {
  season_number: number;
  episode_count?: number;
  title?: string | null;
}

export interface EpisodeSummary {
  content_id: string;
  title: string;
  season_number?: number;
  episode_number?: number;
  overview?: string | null;
  poster_url?: string | null;
}

export async function fetchSeasons(
  session: PrairieSession,
  seriesId: string,
  fetchImpl?: typeof fetch,
): Promise<SeasonSummary[]> {
  const data = await apiRequest<{ seasons?: SeasonSummary[] } | SeasonSummary[]>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/series/${encodeURIComponent(seriesId)}/seasons`,
  );
  if (Array.isArray(data)) return data;
  return data.seasons ?? [];
}

export async function fetchEpisodes(
  session: PrairieSession,
  seriesId: string,
  seasonNumber: number,
  fetchImpl?: typeof fetch,
): Promise<EpisodeSummary[]> {
  const data = await apiRequest<{ episodes?: EpisodeSummary[] } | EpisodeSummary[]>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/series/${encodeURIComponent(seriesId)}/seasons/${seasonNumber}/episodes`,
  );
  if (Array.isArray(data)) return data;
  return data.episodes ?? [];
}
