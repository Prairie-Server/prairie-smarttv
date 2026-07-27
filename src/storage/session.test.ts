import { describe, expect, it } from "vitest";
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

  it("migrates legacy tokens from localStorage into sessionStorage", () => {
    const storage = memoryStorage({
      "prairie.session": JSON.stringify({
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        refreshToken: "legacy-ref",
        username: "ada",
        profileId: "p1",
      }),
    });
    const tokensStorage = memoryStorage();
    expect(loadSession(storage, tokensStorage)).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
      profileToken: undefined,
      profileName: undefined,
    });
    const raw = JSON.parse(storage.getItem("prairie.session")!);
    expect(raw.accessToken).toBeUndefined();
    expect(raw.refreshToken).toBeUndefined();
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
});
