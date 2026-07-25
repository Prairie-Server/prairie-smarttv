import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

export interface Library {
  id: number;
  name: string;
  type: string;
  sort_order?: number;
  poster_url?: string | null;
}

export async function fetchLibraries(
  session: PrairieSession,
  fetchImpl?: typeof fetch,
): Promise<Library[]> {
  const data = await apiRequest<Library[] | { libraries?: Library[] }>(
    sessionClient(session, fetchImpl),
    "/api/v1/user/libraries",
  );
  if (Array.isArray(data)) return data;
  return data.libraries ?? [];
}
