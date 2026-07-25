import { describe, expect, it } from "vitest";
import {
  clearSession,
  loadSession,
  normalizeServerUrl,
  saveSession,
} from "./session";

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
  it("round-trips a valid session", () => {
    const storage = memoryStorage();
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
    );
    expect(saved.serverUrl).toBe("https://prairie.example");
    expect(loadSession(storage)).toEqual(saved);
  });

  it("returns null for missing, incomplete, or corrupt payloads", () => {
    expect(loadSession(memoryStorage())).toBeNull();
    expect(
      loadSession(memoryStorage({ "prairie.session": JSON.stringify({ serverUrl: "x" }) })),
    ).toBeNull();
    expect(loadSession(memoryStorage({ "prairie.session": "{not-json" }))).toBeNull();
  });

  it("clears the session key but keeps last server URL for reconnect", () => {
    const storage = memoryStorage();
    saveSession(
      {
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        username: "ada",
        profileId: "p1",
      },
      storage,
    );
    clearSession(storage);
    expect(loadSession(storage)).toBeNull();
    expect(storage.getItem("prairie.lastServerUrl")).toBe("https://prairie.example");
  });
});
