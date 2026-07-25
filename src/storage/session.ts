const SESSION_KEY = "prairie.session";

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

function normalizeServerUrl(url: string): string {
  return url.trim().replace(/\/+$/, "");
}

export function loadSession(storage: Pick<Storage, "getItem"> = localStorage): PrairieSession | null {
  try {
    const raw = storage.getItem(SESSION_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PrairieSession>;
    if (!parsed.serverUrl || !parsed.accessToken || !parsed.username || !parsed.profileId) {
      return null;
    }
    return {
      serverUrl: normalizeServerUrl(parsed.serverUrl),
      accessToken: parsed.accessToken,
      refreshToken: parsed.refreshToken,
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
  const normalized: PrairieSession = {
    ...session,
    serverUrl: normalizeServerUrl(session.serverUrl),
  };
  storage.setItem(SESSION_KEY, JSON.stringify(normalized));
  return normalized;
}

export function clearSession(storage: Pick<Storage, "removeItem"> = localStorage): void {
  storage.removeItem(SESSION_KEY);
}

export { normalizeServerUrl };
