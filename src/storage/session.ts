import { SESSION_KEY, normalizeServerUrl, saveLastServerUrl } from "./persist";
import { scheduleDurablePersist } from "./durableStorage";

export { SESSION_KEY, normalizeServerUrl };

export const ACCESS_TOKEN_KEY = "prairie.session.accessToken";
export const REFRESH_TOKEN_KEY = "prairie.session.refreshToken";
export const PROFILE_TOKEN_KEY = "prairie.session.profileToken";

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
  profileAvatarUrl?: string | null;
  profileToken?: string;
}

/**
 * Packaged TV apps tear down the WebView on exit, which clears sessionStorage.
 * Tokens therefore live in localStorage (separate keys from the identity blob)
 * so profile + server survive updates and cold launches. Avoid putting secrets
 * in the `prairie.session` JSON itself so identity stays easy to inspect.
 */
function defaultTokensStorage(): Pick<Storage, "getItem" | "setItem" | "removeItem"> {
  return localStorage;
}

function migrateSessionStorageTokens(tokensStorage: Pick<Storage, "getItem" | "setItem">): void {
  if (typeof sessionStorage === "undefined") return;
  if (tokensStorage === sessionStorage) return;
  try {
    for (const key of [ACCESS_TOKEN_KEY, REFRESH_TOKEN_KEY, PROFILE_TOKEN_KEY]) {
      if (tokensStorage.getItem(key)) continue;
      const fromSession = sessionStorage.getItem(key);
      if (!fromSession) continue;
      tokensStorage.setItem(key, fromSession);
      sessionStorage.removeItem(key);
    }
  } catch {
    // Ignore when sessionStorage is unavailable or blocked.
  }
}

export function loadSession(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
  tokensStorage: Pick<Storage, "getItem" | "setItem"> = defaultTokensStorage(),
): PrairieSession | null {
  try {
    migrateSessionStorageTokens(tokensStorage);

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
      profileAvatarUrl: parsed.profileAvatarUrl ?? null,
    };

    // Tokens must never live inside the identity blob.
    // If we find legacy token fields in the session JSON, migrate them into
    // dedicated token keys, then purge the blob.
    const legacyAccessToken = typeof parsed.accessToken === "string" ? parsed.accessToken : "";
    const legacyRefreshToken =
      typeof parsed.refreshToken === "string" ? parsed.refreshToken : undefined;
    const legacyProfileToken =
      typeof parsed.profileToken === "string" ? parsed.profileToken : undefined;

    if (
      typeof parsed.accessToken === "string" ||
      typeof parsed.refreshToken === "string" ||
      typeof parsed.profileToken === "string"
    ) {
      storage.setItem(
        SESSION_KEY,
        JSON.stringify({
          serverUrl: identity.serverUrl,
          username: identity.username,
          profileId: identity.profileId,
          profileName: identity.profileName,
          profileAvatarUrl: identity.profileAvatarUrl,
        }),
      );
    }

    let accessToken = tokensStorage.getItem(ACCESS_TOKEN_KEY);
    if (!accessToken && legacyAccessToken) {
      tokensStorage.setItem(ACCESS_TOKEN_KEY, legacyAccessToken);
      accessToken = legacyAccessToken;
    }
    if (!accessToken) return null;

    let refreshToken = tokensStorage.getItem(REFRESH_TOKEN_KEY) ?? undefined;
    if (refreshToken === undefined && legacyRefreshToken) {
      tokensStorage.setItem(REFRESH_TOKEN_KEY, legacyRefreshToken);
      refreshToken = legacyRefreshToken;
    }

    let profileToken = tokensStorage.getItem(PROFILE_TOKEN_KEY) ?? undefined;
    if (profileToken === undefined && legacyProfileToken) {
      tokensStorage.setItem(PROFILE_TOKEN_KEY, legacyProfileToken);
      profileToken = legacyProfileToken;
    }

    return {
      ...identity,
      accessToken,
      refreshToken,
      profileToken,
    };
  } catch {
    return null;
  }
}

export function saveSession(
  session: PrairieSession,
  storage: Pick<Storage, "setItem"> = localStorage,
  tokensStorage: Pick<Storage, "setItem" | "removeItem"> = defaultTokensStorage(),
): PrairieSession {
  const normalizedServerUrl = normalizeServerUrl(session.serverUrl);
  const normalized: PrairieSession = { ...session, serverUrl: normalizedServerUrl };

  // Store non-secret identity in the session blob.
  storage.setItem(
    SESSION_KEY,
    JSON.stringify({
      serverUrl: normalized.serverUrl,
      username: normalized.username,
      profileId: normalized.profileId,
      profileName: normalized.profileName,
      profileAvatarUrl: normalized.profileAvatarUrl ?? null,
    }),
  );

  // Store tokens in dedicated durable keys (localStorage by default).
  tokensStorage.setItem(ACCESS_TOKEN_KEY, normalized.accessToken);
  if (normalized.refreshToken) {
    tokensStorage.setItem(REFRESH_TOKEN_KEY, normalized.refreshToken);
  } else {
    try {
      tokensStorage.removeItem(REFRESH_TOKEN_KEY);
    } catch {
      /* ignore */
    }
  }
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
  scheduleDurablePersist();
  return normalized;
}

/**
 * Update access/refresh tokens after a successful refresh without rewriting
 * profile identity. Returns the merged session, or null if none is stored.
 */
export function updateSessionTokens(
  tokens: { accessToken: string; refreshToken?: string },
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
  tokensStorage: Pick<Storage, "getItem" | "setItem" | "removeItem"> = defaultTokensStorage(),
): PrairieSession | null {
  const current = loadSession(storage, tokensStorage);
  if (!current) return null;
  return saveSession(
    {
      ...current,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken ?? current.refreshToken,
    },
    storage,
    tokensStorage,
  );
}

/**
 * Clears the active session tokens. Does NOT remove lastServerUrl or playback
 * settings — those must survive logout and app upgrades.
 */
export function clearSession(
  storage: Pick<Storage, "removeItem"> = localStorage,
  tokensStorage: Pick<Storage, "removeItem"> = defaultTokensStorage(),
): void {
  storage.removeItem(SESSION_KEY);
  tokensStorage.removeItem(ACCESS_TOKEN_KEY);
  tokensStorage.removeItem(REFRESH_TOKEN_KEY);
  tokensStorage.removeItem(PROFILE_TOKEN_KEY);
  try {
    if (typeof sessionStorage !== "undefined") {
      sessionStorage.removeItem(ACCESS_TOKEN_KEY);
      sessionStorage.removeItem(REFRESH_TOKEN_KEY);
      sessionStorage.removeItem(PROFILE_TOKEN_KEY);
    }
  } catch {
    // ignore
  }
}
