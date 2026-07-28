/**
 * Start the Home request before React exists.
 *
 * On a cold launch the sequence used to be strictly serial: parse the bundle,
 * mount React, mount Home, *then* ask the server for rows. The network is idle
 * for the whole first half of that, and on TV hardware both halves are slow.
 * Kicking the request off from `boot()` overlaps it with parse and mount, so the
 * rows land as soon as the screen can show them.
 *
 * The prefetch is scoped to one server + profile and consumed at most once; a
 * mismatch (profile switch, different server) simply falls back to a fresh
 * request.
 */

import { fetchHomeSections, type HomeSection } from "./home";
import type { PrairieSession } from "../storage/session";

interface PendingPrefetch {
  key: string;
  /** Never rejects — a failed prefetch resolves null so Home retries normally. */
  promise: Promise<HomeSection[] | null>;
}

let pending: PendingPrefetch | null = null;

function scopeKey(serverUrl: string, profileId: string | undefined): string {
  return `${serverUrl}|${profileId ?? ""}`;
}

/** Begin the Home fetch for `session`. Safe to call when one is already queued. */
export function startHomePrefetch(session: PrairieSession): void {
  const key = scopeKey(session.serverUrl, session.profileId);
  if (pending?.key === key) return;
  pending = {
    key,
    promise: fetchHomeSections(session).catch(() => null),
  };
}

/**
 * Hand over the in-flight Home request for this scope, if there is one.
 * Returns null when nothing matches, so callers just fetch as usual.
 */
export function takeHomePrefetch(
  serverUrl: string,
  profileId: string | undefined,
): Promise<HomeSection[] | null> | null {
  if (!pending) return null;
  if (pending.key !== scopeKey(serverUrl, profileId)) return null;
  const { promise } = pending;
  pending = null;
  return promise;
}

/** @internal Test helper. */
export function resetHomePrefetchForTests(): void {
  pending = null;
}
