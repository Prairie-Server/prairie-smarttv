import { CACHE_TTL_MS, cachedRequest } from "./requestCache";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface CollectionCard {
  id: string;
  title?: string;
  name?: string;
  poster_url?: string | null;
  item_count?: number;
  featured?: boolean;
  library_id?: number;
}

export interface CollectionGroup {
  id?: string;
  name?: string;
  collections: CollectionCard[];
}

export interface LibraryCollectionsResponse {
  library_id?: number;
  groups?: CollectionGroup[];
  ungrouped?: { collections?: CollectionCard[] };
}

export interface PersonalCollectionsResponse {
  collections?: CollectionCard[];
  groups?: CollectionGroup[];
}

function flattenLibraryCollections(
  libraryId: number,
  data: LibraryCollectionsResponse,
): CollectionCard[] {
  const out: CollectionCard[] = [];
  for (const group of data.groups ?? []) {
    for (const card of group.collections ?? []) {
      out.push({ ...card, library_id: libraryId, title: card.title ?? card.name });
    }
  }
  for (const card of data.ungrouped?.collections ?? []) {
    out.push({ ...card, library_id: libraryId, title: card.title ?? card.name });
  }
  return out;
}

export async function fetchLibraryCollections(
  session: PrairieSession,
  libraryId: number,
  fetchImpl?: typeof fetch,
): Promise<CollectionCard[]> {
  const data = await cachedRequest<LibraryCollectionsResponse>(
    sessionClient(session, fetchImpl),
    `/api/v1/library/${libraryId}/collections`,
    CACHE_TTL_MS.collections,
  );
  return flattenLibraryCollections(libraryId, data);
}

export async function fetchPersonalCollections(
  session: PrairieSession,
  fetchImpl?: typeof fetch,
): Promise<CollectionCard[]> {
  const data = await cachedRequest<PersonalCollectionsResponse>(
    sessionClient(session, fetchImpl),
    "/api/v1/collections",
    CACHE_TTL_MS.collections,
  );
  const out: CollectionCard[] = [];
  for (const card of data.collections ?? []) {
    out.push({ ...card, title: card.title ?? card.name });
  }
  for (const group of data.groups ?? []) {
    for (const card of group.collections ?? []) {
      out.push({ ...card, title: card.title ?? card.name });
    }
  }
  return out;
}
