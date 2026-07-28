import { CACHE_TTL_MS, cachedRequest } from "./requestCache";
import { sessionClient } from "./sessionClient";
import type { CatalogItem } from "./catalog";
import type { PrairieSession } from "../storage/session";

export interface SimilarItemRef {
  media_item_id: string;
  score?: number;
  reason?: string;
}

export interface SimilarItemsResult {
  refs: SimilarItemRef[];
  /**
   * Ready-to-render cards from the server. Present on servers that hydrate
   * recommendations; when absent the caller must look up each ref itself, which
   * costs one item-detail request per card.
   */
  cards: CatalogItem[];
}

export async function fetchSimilarItems(
  session: PrairieSession,
  contentId: string,
  fetchImpl?: typeof fetch,
): Promise<SimilarItemsResult> {
  const data = await cachedRequest<{ items?: SimilarItemRef[]; cards?: CatalogItem[] }>(
    sessionClient(session, fetchImpl),
    `/api/v1/recommendations/similar/${encodeURIComponent(contentId)}`,
    CACHE_TTL_MS.similar,
  );
  return {
    refs: data.items ?? [],
    cards: (data.cards ?? []).filter((card) => Boolean(card?.content_id)),
  };
}
