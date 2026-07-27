import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface SimilarItemRef {
  media_item_id: string;
  score?: number;
  reason?: string;
}

export async function fetchSimilarItems(
  session: PrairieSession,
  contentId: string,
  fetchImpl?: typeof fetch,
): Promise<SimilarItemRef[]> {
  const data = await apiRequest<{ items?: SimilarItemRef[] }>(
    sessionClient(session, fetchImpl),
    `/api/v1/recommendations/similar/${encodeURIComponent(contentId)}`,
  );
  return data.items ?? [];
}
