import { apiRequest } from "./client";
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
  const data = await apiRequest<HomeSectionsResponse>(
    sessionClient(session, fetchImpl),
    "/api/v1/home/sections",
  );
  return (data.sections ?? []).map((section) => ({
    ...section,
    items: section.items ?? [],
  }));
}
