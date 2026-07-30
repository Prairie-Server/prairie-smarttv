import { apiRequest } from "./client";
import { CACHE_TTL_MS, cachedRequest } from "./requestCache";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface MediaItemUserState {
  played?: boolean;
  is_favorite?: boolean;
  in_watchlist?: boolean;
}

export interface CatalogItem {
  content_id: string;
  type: string;
  title: string;
  year?: number | null;
  runtime?: number | null;
  genres?: string[];
  content_rating?: string | null;
  rating_imdb?: number | null;
  overview?: string | null;
  poster_url?: string | null;
  /** Present when the server has an AVIF sibling — prefer over inventing .avif paths. */
  poster_avif_url?: string | null;
  backdrop_url?: string | null;
  backdrop_avif_url?: string | null;
  logo_url?: string | null;
  series_id?: string | null;
  series_title?: string | null;
  season_number?: number | null;
  episode_number?: number | null;
  position_seconds?: number | null;
  duration_seconds?: number | null;
  user_state?: MediaItemUserState | null;
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

/**
 * Only the first page of a grid is worth caching.
 *
 * It is what Back from a title re-requests, and what tab-switching re-requests.
 * Later pages are accumulated into component state that is discarded on unmount,
 * so caching them would hold memory nothing reads. A caller that already carries
 * a `snapshot` is mid-pagination and must reach the server for consistency.
 */
function isCacheableCatalogQuery(query: CatalogQuery): boolean {
  return (query.offset ?? 0) === 0 && !query.snapshot;
}

export async function fetchCatalog(
  session: PrairieSession,
  query: CatalogQuery = {},
  fetchImpl?: typeof fetch,
): Promise<CatalogResponse> {
  const options = sessionClient(session, fetchImpl);
  const path = buildCatalogPath(query);
  const data = isCacheableCatalogQuery(query)
    ? await cachedRequest<CatalogResponse>(options, path, CACHE_TTL_MS.catalogPage)
    : await apiRequest<CatalogResponse>(options, path);
  return {
    ...data,
    items: data.items ?? [],
  };
}

export interface CastMember {
  name: string;
  character?: string;
  order?: number;
  person_id?: string;
  photo_url?: string | null;
}

export interface CrewMember {
  name: string;
  job: string;
  person_id?: string;
  photo_url?: string | null;
}

export interface LeafUserData {
  played?: boolean;
  is_in_progress?: boolean;
  position_seconds?: number | null;
  duration_seconds?: number | null;
  last_file_id?: number | null;
}

export interface ItemAudioTrack {
  title?: string;
  embedded_title?: string;
  language?: string;
  codec?: string;
  layout?: string;
  channels?: number;
  default?: boolean;
}

export interface ItemSubtitleTrack {
  index?: number;
  language?: string;
  codec?: string;
  title?: string;
  forced?: boolean;
  default?: boolean;
  hearing_impaired?: boolean;
}

export interface ItemTrickplaySheet {
  index: number;
  url: string;
}

export interface ItemTrickplay {
  interval_seconds: number;
  width: number;
  height: number;
  tile_columns: number;
  tile_rows: number;
  thumbnail_count: number;
  sheets: ItemTrickplaySheet[];
}

export interface ItemVersion {
  file_id: number;
  resolution?: string | null;
  codec_video?: string | null;
  codec_audio?: string | null;
  hdr?: boolean | null;
  container?: string | null;
  duration?: number | null;
  audio_tracks?: ItemAudioTrack[];
  subtitle_tracks?: ItemSubtitleTrack[];
  trickplay?: ItemTrickplay | null;
}

export interface ItemExtra {
  content_id: string;
  kind: string;
  title?: string;
  duration_seconds?: number;
  file_id?: number;
}

export interface ItemDetail extends CatalogItem {
  tagline?: string | null;
  rating_rt_critic?: number | null;
  rating_rt_audience?: number | null;
  cast?: CastMember[];
  crew?: CrewMember[];
  studios?: string[];
  networks?: string[];
  countries?: string[];
  release_date?: string | null;
  first_air_date?: string | null;
  last_air_date?: string | null;
  show_status?: string | null;
  season_count?: number | null;
  episode_count?: number | null;
  user_data?: LeafUserData | null;
  versions?: ItemVersion[];
  extras?: ItemExtra[];
}

export async function fetchItemDetail(
  session: PrairieSession,
  contentId: string,
  fetchImpl?: typeof fetch,
): Promise<ItemDetail> {
  return cachedRequest<ItemDetail>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/items/${encodeURIComponent(contentId)}`,
    CACHE_TTL_MS.itemDetail,
  );
}

export interface SeasonUserData {
  played?: boolean;
  watched_count?: number;
  unplayed_count?: number;
  in_progress_count?: number;
}

export interface SeasonSummary {
  content_id?: string;
  season_number: number;
  episode_count?: number;
  title?: string | null;
  is_specials?: boolean;
  poster_url?: string | null;
  user_data?: SeasonUserData | null;
}

export interface EpisodeSummary {
  content_id: string;
  title: string;
  season_number?: number;
  episode_number?: number;
  overview?: string | null;
  poster_url?: string | null;
  still_url?: string | null;
  runtime?: number | null;
  air_date?: string | null;
  user_data?: LeafUserData | null;
}

export async function fetchSeasons(
  session: PrairieSession,
  seriesId: string,
  fetchImpl?: typeof fetch,
): Promise<SeasonSummary[]> {
  const data = await cachedRequest<{ seasons?: SeasonSummary[] } | SeasonSummary[]>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/series/${encodeURIComponent(seriesId)}/seasons`,
    CACHE_TTL_MS.seasons,
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
  const data = await cachedRequest<{ episodes?: EpisodeSummary[] } | EpisodeSummary[]>(
    sessionClient(session, fetchImpl),
    `/api/v1/catalog/series/${encodeURIComponent(seriesId)}/seasons/${seasonNumber}/episodes`,
    CACHE_TTL_MS.episodes,
  );
  if (Array.isArray(data)) return data;
  return data.episodes ?? [];
}
