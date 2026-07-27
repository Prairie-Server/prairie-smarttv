import { describe, expect, it } from "vitest";
import { LAST_SERVER_URL_KEY, SESSION_KEY } from "./persist";
import {
  addOrUpdate,
  clearTokens,
  displayName,
  emptyRegistry,
  entryIdFromUrl,
  findByUrl,
  loadRegistry,
  migrateFromLegacy,
  normalizeEntry,
  rememberSession,
  removeServer,
  saveRegistry,
  sessionFromEntry,
  sortedEntries,
  switchTo,
} from "./serverRegistry";

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
  };
}

describe("serverRegistry", () => {
  it("derives stable ids and round-trips the registry", () => {
    const id = entryIdFromUrl(" https://prairie.example.com/// ");
    expect(id.length).toBeGreaterThan(0);
    expect(id).toBe(entryIdFromUrl("https://prairie.example.com"));
    expect(entryIdFromUrl("")).toBe("");

    const storage = memoryStorage();
    const registry = addOrUpdate(
      { activeServerId: "", entries: [], scanCidrs: ["10.0.0.0/24"] },
      {
        url: "https://prairie.example.com",
        fetchedName: "Prairie",
        username: "jonah",
        profileId: "p1",
        accessToken: "tok",
      },
    );
    saveRegistry(registry, storage);
    const loaded = loadRegistry(storage);
    expect(loaded.entries).toHaveLength(1);
    expect(loaded.entries[0]?.fetchedName).toBe("Prairie");
    expect(displayName(loaded.entries[0]!)).toBe("Prairie");
    expect(displayName({ url: "https://x.example", fetchedName: "" })).toBe("https://x.example");
    expect(loaded.scanCidrs).toEqual(["10.0.0.0/24"]);
  });

  it("switches active server and builds sessions from entries", () => {
    let registry = addOrUpdate(
      { activeServerId: "", entries: [], scanCidrs: [] },
      {
        url: "https://a.example.com",
        username: "u",
        profileId: "p",
        profileName: "Primary",
        accessToken: "t1",
        profileToken: "pt",
        lastUsedAt: 10,
      },
    );
    registry = addOrUpdate(registry, {
      url: "https://b.example.com",
      username: "u",
      profileId: "p",
      accessToken: "t2",
      lastUsedAt: 20,
    });
    const idB = entryIdFromUrl("https://b.example.com");
    registry = switchTo(registry, idB);
    expect(registry.activeServerId).toBe(idB);
    const session = sessionFromEntry(registry.entries.find((e) => e.id === idB)!);
    expect(session?.serverUrl).toBe("https://b.example.com");
    expect(session?.accessToken).toBe("t2");
    expect(sortedEntries(registry)[0]?.id).toBe(idB);
    expect(
      sessionFromEntry({
        url: "https://x",
        accessToken: "",
        profileId: "",
        username: "",
        fetchedName: "",
        profileName: "",
        profileToken: "",
        id: "x",
        lastUsedAt: 0,
      }),
    ).toBeNull();
  });

  it("remembers sessions, clears tokens, and removes entries", () => {
    let registry = rememberSession(
      { activeServerId: "", entries: [], scanCidrs: [] },
      {
        serverUrl: "https://mem.example.com",
        accessToken: "tok",
        username: "u",
        profileId: "p1",
        profileName: "Kid",
        profileToken: "pt",
      },
      "Named",
    );
    const id = entryIdFromUrl("https://mem.example.com");
    expect(registry.activeServerId).toBe(id);
    expect(registry.entries[0]?.fetchedName).toBe("Named");

    registry = addOrUpdate(registry, { url: "https://mem.example.com", username: "u2" });
    expect(registry.entries[0]?.accessToken).toBe("tok");
    expect(registry.entries[0]?.username).toBe("u2");

    registry = clearTokens(registry, id);
    expect(registry.entries[0]?.accessToken).toBe("");
    expect(registry.entries[0]?.profileId).toBe("");

    registry = addOrUpdate(registry, {
      url: "https://other.example.com",
      accessToken: "t",
      username: "u",
      profileId: "p",
    });
    const otherId = entryIdFromUrl("https://other.example.com");
    registry.activeServerId = id;
    registry = removeServer(registry, id);
    expect(registry.entries).toHaveLength(1);
    expect(registry.activeServerId).toBe(otherId);
    registry = removeServer(registry, otherId);
    expect(registry.entries).toHaveLength(0);
    expect(registry.activeServerId).toBe("");
    expect(removeServer(registry, "missing")).toBe(registry);
    expect(clearTokens(registry, "missing")).toBe(registry);
  });

  it("preserves existing optional fields when updating partial entries", () => {
    const url = "https://partial.example.com";
    let registry = addOrUpdate(emptyRegistry(), {
      url,
      fetchedName: "Prairie",
      username: "ada",
      profileId: "p1",
      profileName: "Primary",
      accessToken: "access",
      profileToken: "profile",
      lastUsedAt: 123,
    });

    registry = addOrUpdate(registry, { url });
    expect(registry.entries[0]).toMatchObject({
      fetchedName: "Prairie",
      username: "ada",
      profileId: "p1",
      profileName: "Primary",
      accessToken: "access",
      profileToken: "profile",
      lastUsedAt: 123,
    });

    const inactive = addOrUpdate(registry, {
      url: "https://inactive.example.com",
      lastUsedAt: 999,
    });
    inactive.activeServerId = entryIdFromUrl(url);
    const sorted = sortedEntries(inactive);
    expect(sorted[0]?.id).toBe(entryIdFromUrl(url));
    expect(sorted[1]?.url).toBe("https://inactive.example.com");
    expect(
      sortedEntries({
        activeServerId: "",
        entries: [
          { ...inactive.entries[0]!, lastUsedAt: undefined as unknown as number },
          { ...inactive.entries[1]!, lastUsedAt: undefined as unknown as number },
        ],
        scanCidrs: [],
      }).map((entry) => entry.url),
    ).toEqual([inactive.entries[0]!.url, inactive.entries[1]!.url]);
    expect(switchTo(inactive, "missing")).toBe(inactive);
    expect(addOrUpdate(inactive, { url: "" })).toBe(inactive);
  });

  it("promotes an existing session into the registry", () => {
    const storage = memoryStorage({
      [SESSION_KEY]: JSON.stringify({
        serverUrl: "https://legacy.example.com",
        accessToken: "tok",
        username: "u",
        profileId: "p1",
        profileName: "Primary",
      }),
    });
    const registry = migrateFromLegacy(storage);
    expect(registry.entries).toHaveLength(1);
    expect(registry.entries[0]?.url).toBe("https://legacy.example.com");
    expect(migrateFromLegacy(storage).entries).toHaveLength(1);

    const storage2 = memoryStorage({
      [LAST_SERVER_URL_KEY]: "https://url-only.example.com",
    });
    const fromUrl = migrateFromLegacy(storage2);
    expect(fromUrl.entries[0]?.url).toBe("https://url-only.example.com");

    expect(migrateFromLegacy(memoryStorage()).entries).toEqual([]);

    const populated = memoryStorage({
      "prairie.serverRegistry": JSON.stringify({
        entries: [{ url: "https://already.example.com" }],
      }),
    });
    expect(migrateFromLegacy(populated).entries[0]?.url).toBe("https://already.example.com");
  });

  it("normalizes entries and tolerates corrupt registry blobs", () => {
    expect(normalizeEntry(null)).toBeNull();
    expect(normalizeEntry({ url: "" })).toBeNull();
    expect(normalizeEntry({ url: "https://ok.example", id: "  custom  " })?.id).toBe("  custom  ");
    expect(emptyRegistry().entries).toEqual([]);

    const storage = memoryStorage({
      "prairie.serverRegistry": "{not-json",
    });
    expect(loadRegistry(storage).entries).toEqual([]);

    const blank = memoryStorage({ "prairie.serverRegistry": "   " });
    expect(loadRegistry(blank).entries).toEqual([]);

    const mixed = memoryStorage({
      "prairie.serverRegistry": JSON.stringify({
        activeServerId: 12,
        entries: [{ url: "https://keep.example" }, { url: "" }, null],
        scanCidrs: [" 10.0.0.0/24 ", 5, ""],
      }),
    });
    const loaded = loadRegistry(mixed);
    expect(loaded.entries).toHaveLength(1);
    expect(loaded.scanCidrs).toEqual(["10.0.0.0/24"]);
    expect(findByUrl(loaded, "https://keep.example")?.url).toBe("https://keep.example");
    expect(findByUrl(loaded, "https://missing.example")).toBeNull();

    saveRegistry(
      {
        // @ts-expect-error intentional malformed
        activeServerId: null,
        // @ts-expect-error intentional malformed
        entries: [{ url: "https://save.example" }, { url: "" }],
        // @ts-expect-error intentional malformed
        scanCidrs: null,
      },
      storage,
    );
    expect(JSON.parse(storage.getItem("prairie.serverRegistry")!).entries).toHaveLength(1);
  });
});
