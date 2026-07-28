import { apiRequest } from "./client";
import { invalidateItem } from "./requestCache";
import { sessionClient } from "./sessionClient";
import type { PrairieSession } from "../storage/session";

function itemPath(contentId: string): string {
  return encodeURIComponent(contentId);
}

/**
 * Every one of these writes changes state that cached reads render: the badge on
 * a grid card, the toggle on the detail hero, the membership of a Home rail.
 * Dropping those entries after the write means the next screen re-reads once
 * rather than showing a value the user just changed.
 */

export async function setFavorite(
  session: PrairieSession,
  contentId: string,
  favorite: boolean,
  fetchImpl?: typeof fetch,
): Promise<void> {
  await apiRequest(sessionClient(session, fetchImpl), `/api/v1/favorites/${itemPath(contentId)}`, {
    method: favorite ? "PUT" : "DELETE",
  });
  invalidateItem(contentId);
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
  invalidateItem(contentId);
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
  invalidateItem(contentId);
}
