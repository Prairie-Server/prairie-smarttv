import { CACHE_TTL_MS, cachedRequest } from "./requestCache";
import { sessionClient } from "./sessionClient";
import type { CatalogItem } from "./catalog";
import type { PrairieSession } from "../storage/session";

export interface HomeSection {
  id: string;
  section_type: string;
  title: string;
  featured?: boolean;
  item_limit?: number;
  total_count?: number;
  items: CatalogItem[];
}

export interface HomeSectionsResponse {
  sections: HomeSection[];
}

export async function fetchHomeSections(
  session: PrairieSession,
  fetchImpl?: typeof fetch,
): Promise<HomeSection[]> {
  const data = await cachedRequest<HomeSectionsResponse>(
    sessionClient(session, fetchImpl),
    "/api/v1/home/sections",
    CACHE_TTL_MS.homeSections,
  );
  return (data.sections ?? []).map((section) => ({
    ...section,
    items: section.items ?? [],
  }));
}
