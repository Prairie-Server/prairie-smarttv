import { apiRequest } from "./client";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

function itemPath(contentId: string): string {
  return encodeURIComponent(contentId);
}

export async function setFavorite(
  session: PrairieSession,
  contentId: string,
  favorite: boolean,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest(sessionClient(session, fetchImpl), `/api/v1/favorites/${itemPath(contentId)}`, {
    method: favorite ? "PUT" : "DELETE",
  });
}

export async function setWatchlist(
  session: PrairieSession,
  contentId: string,
  inWatchlist: boolean,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest(sessionClient(session, fetchImpl), `/api/v1/watchlist/${itemPath(contentId)}`, {
    method: inWatchlist ? "PUT" : "DELETE",
  });
}

export async function setWatched(
  session: PrairieSession,
  contentId: string,
  played: boolean,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest(sessionClient(session, fetchImpl), `/api/v1/watched/${itemPath(contentId)}`, {
    method: played ? "POST" : "DELETE",
  });
}
