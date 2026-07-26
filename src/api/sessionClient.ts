import type { ApiClientOptions } from "./client";
import type { PrairieSession } from "../storage/session";

/** App-level 401/auth-expiry handler (clears session → Connect). */
let unauthorizedHandler: (() => void) | undefined;

export function setSessionUnauthorizedHandler(handler: (() => void) | undefined): void {
  unauthorizedHandler = handler;
}

/** Build ApiClientOptions from a signed-in browse session. */
export function sessionClient(session: PrairieSession, fetchImpl?: typeof fetch): ApiClientOptions {
  return {
    serverUrl: session.serverUrl,
    accessToken: session.accessToken,
    profileId: session.profileId,
    profileToken: session.profileToken,
    fetchImpl,
    onUnauthorized: unauthorizedHandler,
  };
}
