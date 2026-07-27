import { SESSION_KEY, normalizeServerUrl, saveLastServerUrl } from "./persist";

export { SESSION_KEY, normalizeServerUrl };

const ACCESS_TOKEN_KEY = "prairie.session.accessToken";
const PROFILE_TOKEN_KEY = "prairie.session.profileToken";

/** Tokens after login, before a household profile is chosen. */
export interface AuthTokens {
  serverUrl: string;
  accessToken: string;
  refreshToken?: string;
  username: string;
}

/** Fully authenticated browse session with an active profile. */
export interface PrairieSession extends AuthTokens {
  profileId: string;
  profileName?: string;
  profileToken?: string;
}

export function loadSession(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
  tokensStorage: Pick<Storage, "getItem" | "setItem"> = sessionStorage,
): PrairieSession | null {
  try {
    const raw = storage.getItem(SESSION_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PrairieSession>;
    if (!parsed.serverUrl || !parsed.username || !parsed.profileId) {
      return null;
    }

    const identity = {
      serverUrl: normalizeServerUrl(parsed.serverUrl),
      username: parsed.username,
      profileId: parsed.profileId,
      profileName: parsed.profileName,
    };

    // Tokens must never persist in localStorage.
    // If we find legacy token fields in the session blob, migrate them into
    // sessionStorage for this runtime, then purge localStorage.
    const legacyAccessToken = typeof parsed.accessToken === "string" ? parsed.accessToken : "";
    const legacyProfileToken = typeof parsed.profileToken === "string" ? parsed.profileToken : undefined;

    if (typeof parsed.accessToken === "string" || typeof parsed.profileToken === "string") {
      storage.setItem(
        SESSION_KEY,
        JSON.stringify({
          serverUrl: identity.serverUrl,
          username: identity.username,
          profileId: identity.profileId,
          profileName: identity.profileName,
        }),
      );
    }

    let accessToken = tokensStorage.getItem(ACCESS_TOKEN_KEY);
    if (!accessToken && legacyAccessToken) {
      tokensStorage.setItem(ACCESS_TOKEN_KEY, legacyAccessToken);
      accessToken = legacyAccessToken;
    }
    if (!accessToken) return null;

    let profileToken = tokensStorage.getItem(PROFILE_TOKEN_KEY) ?? undefined;
    if (profileToken === undefined && legacyProfileToken) {
      tokensStorage.setItem(PROFILE_TOKEN_KEY, legacyProfileToken);
      profileToken = legacyProfileToken;
    }

    // refreshToken is optional for forward-compat but intentionally not restored —
    // unused refresh tokens must not linger in session memory until refresh ships.
    return {
      ...identity,
      accessToken,
      profileToken,
    };
  } catch {
    return null;
  }
}

export function saveSession(
  session: PrairieSession,
  storage: Pick<Storage, "setItem"> = localStorage,
  tokensStorage: Pick<Storage, "setItem" | "removeItem"> = sessionStorage,
): PrairieSession {
  // Never write refreshToken to localStorage until token refresh is implemented.
  const { refreshToken: _omitRefresh, ...withoutRefresh } = session;

  const normalizedServerUrl = normalizeServerUrl(session.serverUrl);
  const normalized: PrairieSession = { ...withoutRefresh, serverUrl: normalizedServerUrl };

  // Store non-secret identity in localStorage.
  storage.setItem(
    SESSION_KEY,
    JSON.stringify({
      serverUrl: normalized.serverUrl,
      username: normalized.username,
      profileId: normalized.profileId,
      profileName: normalized.profileName,
    }),
  );

  // Store tokens in sessionStorage.
  tokensStorage.setItem(ACCESS_TOKEN_KEY, normalized.accessToken);
  if (normalized.profileToken) {
    tokensStorage.setItem(PROFILE_TOKEN_KEY, normalized.profileToken);
  } else {
    // Ensure we don't keep an old profile token around.
    try {
      tokensStorage.removeItem(PROFILE_TOKEN_KEY);
    } catch {
      // ignore when removeItem is not present (typing) or available in environment
    }
  }

  // Keep last server URL even if the user later disconnects (pre-fill Connect).
  saveLastServerUrl(normalized.serverUrl, storage);
  return normalized;
}

/**
 * Clears the active session tokens. Does NOT remove lastServerUrl or playback
 * settings — those must survive logout and app upgrades.
 */
export function clearSession(
  storage: Pick<Storage, "removeItem"> = localStorage,
  tokensStorage: Pick<Storage, "removeItem"> = sessionStorage,
): void {
  storage.removeItem(SESSION_KEY);
  tokensStorage.removeItem(ACCESS_TOKEN_KEY);
  tokensStorage.removeItem(PROFILE_TOKEN_KEY);
}
