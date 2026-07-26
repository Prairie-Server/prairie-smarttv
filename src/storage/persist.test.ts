import { describe, expect, it } from "vitest";
import {
  LAST_SERVER_URL_KEY,
  PRESERVED_STORAGE_KEYS,
  SERVER_REGISTRY_KEY,
  SESSION_KEY,
  STORAGE_SCHEMA_KEY,
  ensureStorageSchema,
  loadLastServerUrl,
  saveLastServerUrl,
} from "./persist";

function memoryStorage(initial: Record<string, string> = {}) {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => map.get(key) ?? null,
    setItem: (key: string, value: string) => {
      map.set(key, value);
    },
    removeItem: (key: string) => {
      map.delete(key);
    },
    keys: () => [...map.keys()],
  };
}

describe("persist / upgrade safety", () => {
  it("lists the keys that must survive upgrades", () => {
    expect(PRESERVED_STORAGE_KEYS).toContain(SESSION_KEY);
    expect(PRESERVED_STORAGE_KEYS).toContain(LAST_SERVER_URL_KEY);
    expect(PRESERVED_STORAGE_KEYS).toContain(SERVER_REGISTRY_KEY);
  });

  it("promotes server URL from session on schema v0 → v2 without wiping session", () => {
    const storage = memoryStorage({
      [SESSION_KEY]: JSON.stringify({
        serverUrl: "https://prairie.example/",
        accessToken: "tok",
        username: "ada",
        profileId: "p1",
      }),
    });
    const version = ensureStorageSchema(storage);
    expect(version).toBe(2);
    expect(storage.getItem(STORAGE_SCHEMA_KEY)).toBe("2");
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://prairie.example");
    // Session blob must still be intact after upgrade migration.
    expect(JSON.parse(storage.getItem(SESSION_KEY)!).accessToken).toBe("tok");
  });

  it("bumps v1 → v2 without clearing session or last URL", () => {
    const storage = memoryStorage({
      [STORAGE_SCHEMA_KEY]: "1",
      [SESSION_KEY]: JSON.stringify({ accessToken: "keep" }),
      [LAST_SERVER_URL_KEY]: "https://keep.example",
    });
    expect(ensureStorageSchema(storage)).toBe(2);
    expect(storage.getItem(SESSION_KEY)).toContain("keep");
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://keep.example");
  });

  it("does not clear existing keys when schema is already current", () => {
    const storage = memoryStorage({
      [STORAGE_SCHEMA_KEY]: "2",
      [SESSION_KEY]: JSON.stringify({ accessToken: "keep" }),
      [LAST_SERVER_URL_KEY]: "https://keep.example",
      [SERVER_REGISTRY_KEY]: JSON.stringify({ entries: [] }),
    });
    ensureStorageSchema(storage);
    expect(storage.getItem(SESSION_KEY)).toContain("keep");
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://keep.example");
    expect(storage.getItem(SERVER_REGISTRY_KEY)).toContain("entries");
  });

  it("loads last server URL from dedicated key or session fallback", () => {
    const dedicated = memoryStorage({ [LAST_SERVER_URL_KEY]: "https://a.example/" });
    expect(loadLastServerUrl(dedicated)).toBe("https://a.example");

    const fromSession = memoryStorage({
      [SESSION_KEY]: JSON.stringify({ serverUrl: "https://b.example" }),
    });
    expect(loadLastServerUrl(fromSession)).toBe("https://b.example");
  });

  it("saves last server URL normalized", () => {
    const storage = memoryStorage();
    saveLastServerUrl("https://c.example///", storage);
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://c.example");
  });

  it("ignores empty last-server saves and corrupt session fallbacks", () => {
    const storage = memoryStorage();
    saveLastServerUrl("   ", storage);
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBeNull();

    const corrupt = memoryStorage({ [SESSION_KEY]: "{not-json" });
    expect(loadLastServerUrl(corrupt)).toBe("");

    const noUrl = memoryStorage({
      [SESSION_KEY]: JSON.stringify({ accessToken: "tok" }),
    });
    expect(loadLastServerUrl(noUrl)).toBe("");
  });

  it("skips session promotion when lastServerUrl already exists", () => {
    const storage = memoryStorage({
      [LAST_SERVER_URL_KEY]: "https://already.example",
      [SESSION_KEY]: JSON.stringify({ serverUrl: "https://other.example" }),
    });
    ensureStorageSchema(storage);
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://already.example");
  });

  it("handles non-numeric schema versions as v0", () => {
    const storage = memoryStorage({
      [STORAGE_SCHEMA_KEY]: "nope",
      [SESSION_KEY]: JSON.stringify({ serverUrl: "https://d.example" }),
    });
    expect(ensureStorageSchema(storage)).toBe(2);
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://d.example");
  });

  it("leaves a current schema version unchanged", () => {
    const storage = memoryStorage({
      [STORAGE_SCHEMA_KEY]: "2",
      [LAST_SERVER_URL_KEY]: "https://stable.example",
    });
    expect(ensureStorageSchema(storage)).toBe(2);
    expect(storage.getItem(LAST_SERVER_URL_KEY)).toBe("https://stable.example");
  });
});
