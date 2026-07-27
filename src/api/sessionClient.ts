import type { ApiClientOptions } from "./client";
import type { PrairieSession } from "../storage/session";

/** App-level 401/auth-expiry handler (clears session → Connect). */
let unauthorizedHandler: (() => void) | undefined;
/** App-level handler when access/refresh tokens are renewed. */
let tokensRefreshedHandler:
  | ((tokens: { accessToken: string; refreshToken?: string }) => void)
  | undefined;

export function setSessionUnauthorizedHandler(handler: (() => void) | undefined): void {
  unauthorizedHandler = handler;
}

export function setSessionTokensRefreshedHandler(
  handler: ((tokens: { accessToken: string; refreshToken?: string }) => void) | undefined,
): void {
  tokensRefreshedHandler = handler;
}

/** Build ApiClientOptions from a signed-in browse session. */
export function sessionClient(session: PrairieSession, fetchImpl?: typeof fetch): ApiClientOptions {
  return {
    serverUrl: session.serverUrl,
    accessToken: session.accessToken,
    refreshToken: session.refreshToken,
    profileId: session.profileId,
    profileToken: session.profileToken,
    fetchImpl,
    onUnauthorized: unauthorizedHandler,
    onTokensRefreshed: tokensRefreshedHandler,
  };
}
