import { SERVER_REGISTRY_KEY, loadLastServerUrl, normalizeServerUrl } from "./persist";
import { loadSession, type PrairieSession } from "./session";

export { SERVER_REGISTRY_KEY };

export interface ServerEntry {
  id: string;
  url: string;
  fetchedName: string;
  username: string;
  profileId: string;
  profileName: string;
  accessToken: string;
  profileToken: string;
  lastUsedAt: number;
}

export interface ServerRegistry {
  activeServerId: string;
  entries: ServerEntry[];
  scanCidrs: string[];
}

export function emptyRegistry(): ServerRegistry {
  return { activeServerId: "", entries: [], scanCidrs: [] };
}

/** Stable client-derived ID: base64url of the normalized URL (Roku/Apple-shaped). */
export function entryIdFromUrl(url: string): string {
  const normalized = normalizeServerUrl(url);
  if (!normalized) return "";
  const bytes = btoa(normalized);
  return bytes.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function normalizeEntry(entry: Partial<ServerEntry> | null | undefined): ServerEntry | null {
  if (!entry || typeof entry !== "object") return null;
  const url = entry.url ? normalizeServerUrl(entry.url) : "";
  if (!url) return null;
  const id = entry.id?.trim() ? entry.id : entryIdFromUrl(url);
  return {
    id,
    url,
    fetchedName: entry.fetchedName ?? "",
    username: entry.username ?? "",
    profileId: entry.profileId ?? "",
    profileName: entry.profileName ?? "",
    accessToken: entry.accessToken ?? "",
    profileToken: entry.profileToken ?? "",
    lastUsedAt: typeof entry.lastUsedAt === "number" ? entry.lastUsedAt : 0,
  };
}

export function displayName(entry: Pick<ServerEntry, "url" | "fetchedName">): string {
  const name = entry.fetchedName?.trim();
  return name || entry.url;
}

export function loadRegistry(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
): ServerRegistry {
  const registry = emptyRegistry();
  let hadPersistedTokens = false;
  try {
    const raw = storage.getItem(SERVER_REGISTRY_KEY);
    if (!raw?.trim()) return registry;
    const parsed = JSON.parse(raw) as Partial<ServerRegistry>;
    if (typeof parsed.activeServerId === "string") {
      registry.activeServerId = parsed.activeServerId;
    }
    if (Array.isArray(parsed.entries)) {
      for (const entry of parsed.entries) {
        const normalized = normalizeEntry(entry);
        if (normalized) {
          // Token material must never persist in localStorage.
          if (normalized.accessToken || normalized.profileToken) hadPersistedTokens = true;
          normalized.accessToken = "";
          normalized.profileToken = "";
          registry.entries.push(normalized);
        }
      }
    }
    if (Array.isArray(parsed.scanCidrs)) {
      for (const cidr of parsed.scanCidrs) {
        if (typeof cidr === "string" && cidr.trim()) registry.scanCidrs.push(cidr.trim());
      }
    }
  } catch {
    /* corrupt blob → empty registry */
  }

  if (hadPersistedTokens) {
    // Purge legacy token material from localStorage.
    saveRegistry(registry, storage);
  }

  return registry;
}

export function saveRegistry(
  registry: ServerRegistry,
  storage: Pick<Storage, "setItem"> = localStorage,
): void {
  const payload: ServerRegistry = {
    activeServerId: registry.activeServerId ?? "",
    entries: [],
    scanCidrs: Array.isArray(registry.scanCidrs) ? [...registry.scanCidrs] : [],
  };
  for (const entry of registry.entries) {
    const normalized = normalizeEntry(entry);
    if (normalized) {
      // Never persist token material in localStorage.
      normalized.accessToken = "";
      normalized.profileToken = "";
      payload.entries.push(normalized);
    }
  }
  storage.setItem(SERVER_REGISTRY_KEY, JSON.stringify(payload));
}

export function findIndex(registry: ServerRegistry, serverId: string): number {
  return registry.entries.findIndex((entry) => entry.id === serverId);
}

export function findByUrl(registry: ServerRegistry, url: string): ServerEntry | null {
  const idx = findIndex(registry, entryIdFromUrl(url));
  return idx < 0 ? null : (registry.entries[idx] ?? null);
}

export function sortedEntries(registry: ServerRegistry): ServerEntry[] {
  const activeId = registry.activeServerId ?? "";
  return [...registry.entries].sort((a, b) => {
    if (a.id === activeId && b.id !== activeId) return -1;
    if (b.id === activeId && a.id !== activeId) return 1;
    return (b.lastUsedAt ?? 0) - (a.lastUsedAt ?? 0);
  });
}

function nowSeconds(): number {
  return Math.floor(Date.now() / 1000);
}

export function addOrUpdate(registry: ServerRegistry, entry: Partial<ServerEntry>): ServerRegistry {
  const normalized = normalizeEntry(entry);
  if (!normalized) return registry;
  const idx = findIndex(registry, normalized.id);
  if (idx >= 0) {
    const existing = registry.entries[idx]!;
    if (!normalized.profileId && existing.profileId) normalized.profileId = existing.profileId;
    if (!normalized.profileName && existing.profileName) {
      normalized.profileName = existing.profileName;
    }
    if (!normalized.accessToken && existing.accessToken) {
      normalized.accessToken = existing.accessToken;
    }
    if (!normalized.profileToken && existing.profileToken) {
      normalized.profileToken = existing.profileToken;
    }
    if (!normalized.fetchedName && existing.fetchedName) {
      normalized.fetchedName = existing.fetchedName;
    }
    if (!normalized.username && existing.username) normalized.username = existing.username;
    if (!normalized.lastUsedAt) normalized.lastUsedAt = existing.lastUsedAt;
    registry.entries[idx] = normalized;
  } else {
    if (!normalized.lastUsedAt) normalized.lastUsedAt = nowSeconds();
    registry.entries.push(normalized);
  }
  return registry;
}

export function removeServer(registry: ServerRegistry, serverId: string): ServerRegistry {
  const idx = findIndex(registry, serverId);
  if (idx < 0) return registry;
  registry.entries.splice(idx, 1);
  if (registry.activeServerId === serverId) {
    registry.activeServerId = "";
    if (registry.entries.length > 0) {
      registry.activeServerId = sortedEntries(registry)[0]!.id;
    }
  }
  return registry;
}

export function switchTo(registry: ServerRegistry, serverId: string): ServerRegistry {
  const idx = findIndex(registry, serverId);
  if (idx < 0) return registry;
  registry.activeServerId = serverId;
  registry.entries[idx]!.lastUsedAt = nowSeconds();
  return registry;
}

export function rememberSession(
  registry: ServerRegistry,
  session: PrairieSession,
  fetchedName = "",
): ServerRegistry {
  const next = addOrUpdate(registry, {
    url: session.serverUrl,
    username: session.username,
    profileId: session.profileId,
    profileName: session.profileName ?? "",
    accessToken: session.accessToken,
    profileToken: session.profileToken ?? "",
    fetchedName,
    lastUsedAt: nowSeconds(),
  });
  next.activeServerId = entryIdFromUrl(session.serverUrl);
  return next;
}

export function sessionFromEntry(entry: ServerEntry | null | undefined): PrairieSession | null {
  if (!entry?.accessToken || !entry.profileId || !entry.username) return null;
  return {
    serverUrl: entry.url,
    accessToken: entry.accessToken,
    username: entry.username,
    profileId: entry.profileId,
    profileName: entry.profileName || undefined,
    profileToken: entry.profileToken || undefined,
  };
}

export function clearTokens(registry: ServerRegistry, serverId: string): ServerRegistry {
  const idx = findIndex(registry, serverId);
  if (idx < 0) return registry;
  registry.entries[idx] = {
    ...registry.entries[idx]!,
    accessToken: "",
    profileToken: "",
  };
  return registry;
}

/** Promote legacy single lastServerUrl/session into the registry (schema v2). */
export function migrateFromLegacy(
  storage: Pick<Storage, "getItem" | "setItem"> = localStorage,
): ServerRegistry {
  const registry = loadRegistry(storage);
  if (registry.entries.length > 0) return registry;

  const session = loadSession(storage);
  const lastUrl = loadLastServerUrl(storage);
  let next = registry;
  if (session) {
    next = rememberSession(next, session, "");
  } else if (lastUrl) {
    next = addOrUpdate(next, { url: lastUrl, lastUsedAt: nowSeconds() });
    next.activeServerId = entryIdFromUrl(lastUrl);
  }
  if (next.entries.length > 0) {
    saveRegistry(next, storage);
  }
  return next;
}
