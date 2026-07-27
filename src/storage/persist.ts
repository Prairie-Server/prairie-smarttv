/**
 * Cross-upgrade persistence helpers.
 *
 * Identity rules (do not break without a migration):
 * - localStorage keys stay on the `prairie.*` prefix
 * - Tizen package id `PrairieApp` / app id `PrairieApp.Prairie` (legacy: `PrairieLte`)
 * - webOS app id `org.prairieserver.prairie`
 *
 * Keep those package ids stable across releases. Changing them wipes WebView
 * localStorage (Moonfin avoids this by never rotating package ids). Prairie
 * also mirrors keys into Tizen `documents` via durableStorage.ts for sideload
 * reinstall recovery.
 *
 * Schema bumps must be additive. Never clear session or settings keys on upgrade.
 */

export const STORAGE_SCHEMA_KEY = "prairie.storageSchemaVersion";
/** Bump only when additive migrations are required. Never wipe on bump. */
export const STORAGE_SCHEMA_VERSION = 2;

export const LAST_SERVER_URL_KEY = "prairie.lastServerUrl";
export const SESSION_KEY = "prairie.session";
export const PLAYBACK_SETTINGS_KEY = "prairie.playbackSettings";
export const SERVER_REGISTRY_KEY = "prairie.serverRegistry";

/** Keys that must survive app updates. Cleared only by explicit user logout. */
export const PRESERVED_STORAGE_KEYS = [
  SESSION_KEY,
  PLAYBACK_SETTINGS_KEY,
  LAST_SERVER_URL_KEY,
  SERVER_REGISTRY_KEY,
  STORAGE_SCHEMA_KEY,
] as const;

export function normalizeServerUrl(url: string): string {
  return url.trim().replace(/\/+$/, "");
}

export function loadLastServerUrl(storage: Pick<Storage, "getItem"> = localStorage): string {
  try {
    const direct = storage.getItem(LAST_SERVER_URL_KEY);
    if (direct?.trim()) return normalizeServerUrl(direct);
    const sessionRaw = storage.getItem(SESSION_KEY);
    if (!sessionRaw) return "";
    const parsed = JSON.parse(sessionRaw) as { serverUrl?: string };
    return parsed.serverUrl ? normalizeServerUrl(parsed.serverUrl) : "";
  } catch {
    return "";
  }
}

export function saveLastServerUrl(
  url: string,
  storage: Pick<Storage, "setItem"> = localStorage,
): void {
  const normalized = normalizeServerUrl(url);
  if (normalized) storage.setItem(LAST_SERVER_URL_KEY, normalized);
}

/**
 * Ensure schema version is recorded. Migrations may copy/rename keys but must
 * not remove PRESERVED_STORAGE_KEYS. Safe to call on every boot.
 */
export function ensureStorageSchema(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
): number {
  let current = 0;
  try {
    const raw = storage.getItem(STORAGE_SCHEMA_KEY);
    current = raw ? Number.parseInt(raw, 10) || 0 : 0;
  } catch {
    // keep current at 0 when storage is unavailable
  }

  // v0 → v1: promote server URL out of the session blob so Connect still
  // pre-fills after a partial/corrupt session without wiping tokens.
  if (current < 1) {
    try {
      const existing = storage.getItem(LAST_SERVER_URL_KEY);
      if (!existing) {
        const sessionRaw = storage.getItem(SESSION_KEY);
        if (sessionRaw) {
          const parsed = JSON.parse(sessionRaw) as { serverUrl?: string };
          if (parsed.serverUrl) {
            storage.setItem(LAST_SERVER_URL_KEY, normalizeServerUrl(parsed.serverUrl));
          }
        }
      }
    } catch {
      /* leave keys untouched */
    }
    storage.setItem(STORAGE_SCHEMA_KEY, "1");
    current = 1;
  }

  // v1 → v2: registry key introduced. Migration of session/last URL into
  // prairie.serverRegistry is performed by migrateFromLegacy on boot
  // (avoids a persist ↔ registry import cycle at call sites).
  if (current < 2) {
    storage.setItem(STORAGE_SCHEMA_KEY, String(STORAGE_SCHEMA_VERSION));
    return STORAGE_SCHEMA_VERSION;
  }

  // Future additive migrations land here as `if (current < N) { … }` blocks.
  // Never delete PRESERVED_STORAGE_KEYS.
  return current;
}
