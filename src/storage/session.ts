import {
  SESSION_KEY,
  normalizeServerUrl,
  saveLastServerUrl,
} from "./persist";

export { SESSION_KEY, normalizeServerUrl };

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

export function loadSession(storage: Pick<Storage, "getItem"> = localStorage): PrairieSession | null {
  try {
    const raw = storage.getItem(SESSION_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PrairieSession>;
    if (!parsed.serverUrl || !parsed.accessToken || !parsed.username || !parsed.profileId) {
      return null;
    }
    // refreshToken is optional for forward-compat but intentionally not restored —
    // unused refresh tokens must not linger in session memory until refresh ships.
    return {
      serverUrl: normalizeServerUrl(parsed.serverUrl),
      accessToken: parsed.accessToken,
      username: parsed.username,
      profileId: parsed.profileId,
      profileName: parsed.profileName,
      profileToken: parsed.profileToken,
    };
  } catch {
    return null;
  }
}

export function saveSession(
  session: PrairieSession,
  storage: Pick<Storage, "setItem"> = localStorage,
): PrairieSession {
  // Never write refreshToken to localStorage until token refresh is implemented.
  const { refreshToken: _omitRefresh, ...withoutRefresh } = session;
  const normalized: PrairieSession = {
    ...withoutRefresh,
    serverUrl: normalizeServerUrl(session.serverUrl),
  };
  storage.setItem(SESSION_KEY, JSON.stringify(normalized));
  // Keep last server URL even if the user later disconnects (pre-fill Connect).
  saveLastServerUrl(normalized.serverUrl, storage);
  return normalized;
}

/**
 * Clears the active session tokens. Does NOT remove lastServerUrl or playback
 * settings — those must survive logout and app upgrades.
 */
export function clearSession(storage: Pick<Storage, "removeItem"> = localStorage): void {
  storage.removeItem(SESSION_KEY);
}
