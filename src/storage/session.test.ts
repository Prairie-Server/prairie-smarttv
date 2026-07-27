import { afterEach, describe, expect, it } from "vitest";
import { clearSession, loadSession, normalizeServerUrl, saveSession } from "./session";

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

afterEach(() => {
  sessionStorage.clear();
  localStorage.clear();
});

describe("normalizeServerUrl", () => {
  it("trims trailing slashes", () => {
    expect(normalizeServerUrl(" https://prairie.example/// ")).toBe("https://prairie.example");
  });
});

describe("session persistence", () => {
  it("round-trips a valid session without persisting refreshToken", () => {
    const storage = memoryStorage();
    const tokensStorage = memoryStorage();
    const saved = saveSession(
      {
        serverUrl: "https://prairie.example/",
        accessToken: "tok",
        refreshToken: "ref",
        username: "ada",
        profileId: "p1",
        profileName: "Ada",
        profileToken: "pin",
      },
      storage,
      tokensStorage,
    );
    expect(saved.serverUrl).toBe("https://prairie.example");
    expect(saved.refreshToken).toBeUndefined();
    const raw = JSON.parse(storage.getItem("prairie.session")!);
    expect(raw.refreshToken).toBeUndefined();
    expect(raw.accessToken).toBeUndefined();
    expect(raw.profileToken).toBeUndefined();
    expect(loadSession(storage, tokensStorage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileName: "Ada",
      profileToken: "pin",
    });
  });

  it("migrates legacy tokens from the identity blob into dedicated keys", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        refreshToken: "legacy-ref",
        username: "ada",
        profileId: "p1",
        profileToken: "legacy-pin",
      }),
    });
    const tokensStorage = memoryStorage();
    expect(loadSession(storage, tokensStorage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileToken: "legacy-pin",
      profileName: undefined,
    });
    expect(tokensStorage.getItem("prairie.session.accessToken")).toBe("tok");
    expect(tokensStorage.getItem("prairie.session.profileToken")).toBe("legacy-pin");
    const raw = JSON.parse(storage.getItem("prairie.session")!);
    expect(raw.accessToken).toBeUndefined();
    expect(raw.refreshToken).toBeUndefined();
    expect(raw.profileToken).toBeUndefined();
  });

  it("migrates a legacy profileToken into dedicated token keys", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        profileToken: "legacy-pin",
        username: "ada",
        profileId: "p1",
        profileName: "Ada",
      }),
    });
    const tokensStorage = memoryStorage();
    expect(loadSession(storage, tokensStorage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileName: "Ada",
      profileToken: "legacy-pin",
    });
    expect(tokensStorage.getItem("prairie.session.profileToken")).toBe("legacy-pin");
    const raw = JSON.parse(storage.getItem("prairie.session")!);
    expect(raw.profileToken).toBeUndefined();
    expect(raw.accessToken).toBeUndefined();
  });

  it("round-trips tokens through a single durable storage (TV cold launch)", () => {
    const storage = memoryStorage();
    saveSession(
      {
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        username: "ada",
        profileId: "p1",
        profileName: "Ada",
      },
      storage,
      storage,
    );
    expect(loadSession(storage, storage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileName: "Ada",
      profileToken: undefined,
    });
  });

  it("returns null when identity exists but no access token is available", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        username: "ada",
        profileId: "p1",
      }),
    });
    expect(loadSession(storage, memoryStorage())).toBeNull();
  });

  it("returns null for missing, incomplete, or corrupt payloads", () => {
    expect(loadSession(memoryStorage(), memoryStorage())).toBeNull();
    expect(
      loadSession(
        memoryStorage({ "prairie.session": JSON.stringify({ serverUrl: "x" }) }),
        memoryStorage(),
      ),
    ).toBeNull();
    expect(
      loadSession(memoryStorage({ "prairie.session": "{not-json" }), memoryStorage()),
    ).toBeNull();
  });

  it("returns null when no access token is available after migration", () => {
    expect(
      loadSession(
        memoryStorage({
          "prairie.session": JSON.stringify({
            serverUrl: "https://prairie.example",
            username: "ada",
            profileId: "p1",
            profileToken: "pin-only",
          }),
        }),
        memoryStorage(),
      ),
    ).toBeNull();
  });

  it("clears the session key but keeps last server URL for reconnect", () => {
    const storage = memoryStorage();
    const tokensStorage = memoryStorage();
    saveSession(
      {
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        username: "ada",
        profileId: "p1",
      },
      storage,
      tokensStorage,
    );
    clearSession(storage, tokensStorage);
    expect(loadSession(storage, tokensStorage)).toBeNull();
    expect(storage.getItem("prairie.lastServerUrl")).toBe("https://prairie.example");
  });

  it("migrates leftover sessionStorage tokens into durable storage", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        username: "ada",
        profileId: "p1",
        profileName: "Ada",
      }),
    });
    const tokensStorage = memoryStorage();
    sessionStorage.setItem("prairie.session.accessToken", "from-session");
    sessionStorage.setItem("prairie.session.profileToken", "pin-from-session");

    expect(loadSession(storage, tokensStorage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "from-session",
      username: "ada",
      profileId: "p1",
      profileName: "Ada",
      profileToken: "pin-from-session",
    });
    expect(tokensStorage.getItem("prairie.session.accessToken")).toBe("from-session");
    expect(tokensStorage.getItem("prairie.session.profileToken")).toBe("pin-from-session");
    expect(sessionStorage.getItem("prairie.session.accessToken")).toBeNull();
    expect(sessionStorage.getItem("prairie.session.profileToken")).toBeNull();
  });

  it("does not overwrite durable tokens when migrating from sessionStorage", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        username: "ada",
        profileId: "p1",
      }),
    });
    const tokensStorage = memoryStorage({
      "prairie.session.accessToken": "durable",
    });
    sessionStorage.setItem("prairie.session.accessToken", "stale-session");
    sessionStorage.setItem("prairie.session.profileToken", "pin");

    expect(loadSession(storage, tokensStorage)?.accessToken).toBe("durable");
    expect(tokensStorage.getItem("prairie.session.accessToken")).toBe("durable");
    expect(tokensStorage.getItem("prairie.session.profileToken")).toBe("pin");
    expect(sessionStorage.getItem("prairie.session.accessToken")).toBe("stale-session");
    expect(sessionStorage.getItem("prairie.session.profileToken")).toBeNull();
  });

  it("loads when tokensStorage is sessionStorage without double-migrating", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        username: "ada",
        profileId: "p1",
      }),
    });
    sessionStorage.setItem("prairie.session.accessToken", "sess-tok");
    expect(loadSession(storage, sessionStorage)?.accessToken).toBe("sess-tok");
  });

  it("clears leftover sessionStorage token keys on logout", () => {
    const storage = memoryStorage();
    saveSession(
      {
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        username: "ada",
        profileId: "p1",
        profileToken: "pin",
      },
      storage,
      storage,
    );
    sessionStorage.setItem("prairie.session.accessToken", "leftover");
    sessionStorage.setItem("prairie.session.profileToken", "leftover-pin");
    clearSession(storage, storage);
    expect(sessionStorage.getItem("prairie.session.accessToken")).toBeNull();
    expect(sessionStorage.getItem("prairie.session.profileToken")).toBeNull();
  });

  it("uses localStorage defaults for durable TV sessions", () => {
    localStorage.clear();
    sessionStorage.clear();
    saveSession({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileName: "Ada",
    });
    expect(localStorage.getItem("prairie.session.accessToken")).toBe("tok");
    expect(loadSession()).toMatchObject({
      accessToken: "tok",
      profileId: "p1",
      username: "ada",
    });
    clearSession();
    expect(localStorage.getItem("prairie.session")).toBeNull();
    expect(localStorage.getItem("prairie.session.accessToken")).toBeNull();
  });
});
