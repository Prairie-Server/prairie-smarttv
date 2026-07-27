import { describe, expect, it, vi } from "vitest";
import {
  checkAppUpdate,
  DEFAULT_CHANGELOG_URL,
  DEFAULT_RELEASES_LATEST_URL,
} from "./checkAppUpdate";

describe("checkAppUpdate", () => {
  it("reports update available from github latest", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toBe(DEFAULT_RELEASES_LATEST_URL);
      expect(new Headers(init?.headers).get("Accept")).toBe("application/vnd.github+json");
      expect(new Headers(init?.headers).get("User-Agent")).toBe("Prairie-SmartTV");
      return new Response(
        JSON.stringify({
          tag_name: "v1.4.0",
          html_url: "https://github.com/Prairie-Server/prairie-smarttv/releases/tag/v1.4.0",
        }),
        { status: 200 },
      );
    });

    const status = await checkAppUpdate({ currentVersionName: "0.3.11", fetchImpl });
    expect(status).toEqual({
      kind: "updateAvailable",
      currentVersion: "0.3.11",
      latestVersion: "1.4.0",
      releaseUrl: "https://github.com/Prairie-Server/prairie-smarttv/releases/tag/v1.4.0",
      changelogUrl: "https://github.com/Prairie-Server/prairie-smarttv/releases/tag/v1.4.0",
    });
  });

  it("treats 404 as up to date", async () => {
    const fetchImpl = vi.fn(
      async () => new Response(JSON.stringify({ message: "Not Found" }), { status: 404 }),
    );
    const status = await checkAppUpdate({ currentVersionName: "0.3.11", fetchImpl });
    expect(status).toEqual({
      kind: "upToDate",
      currentVersion: "0.3.11",
      latestVersion: "0.3.11",
      changelogUrl: DEFAULT_CHANGELOG_URL,
    });
  });

  it("maps network failure to unavailable", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error("offline");
    });
    const status = await checkAppUpdate({ currentVersionName: "0.3.11", fetchImpl });
    expect(status).toEqual({
      kind: "unavailable",
      currentVersion: "0.3.11",
      changelogUrl: DEFAULT_CHANGELOG_URL,
    });
  });

  it("maps non-success HTTP to unavailable", async () => {
    const fetchImpl = vi.fn(async () => new Response("boom", { status: 500 }));
    const status = await checkAppUpdate({ currentVersionName: "0.1.0", fetchImpl });
    expect(status.kind).toBe("unavailable");
    if (status.kind === "unavailable") {
      expect(status.changelogUrl).toBe(DEFAULT_CHANGELOG_URL);
    }
  });

  it("uses release name when tag_name is missing", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            name: "v0.2.0",
            html_url: "https://github.com/Prairie-Server/prairie-smarttv/releases/tag/v0.2.0",
          }),
          { status: 200 },
        ),
    );
    const status = await checkAppUpdate({ currentVersionName: "0.1.0", fetchImpl });
    expect(status.kind).toBe("updateAvailable");
    if (status.kind === "updateAvailable") {
      expect(status.latestVersion).toBe("0.2.0");
    }
  });

  it("falls back changelog when html_url is missing", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ tag_name: "v0.2.0", html_url: 123 }), { status: 200 }),
    );
    const status = await checkAppUpdate({
      currentVersionName: "0.1.0",
      fetchImpl,
      releasesLatestUrl: "https://example.test/latest",
    });
    expect(status.kind).toBe("updateAvailable");
    if (status.kind === "updateAvailable") {
      expect(status.releaseUrl).toBeNull();
      expect(status.changelogUrl).toBe(DEFAULT_CHANGELOG_URL);
    }
  });

  it("maps abort timeout to unavailable", async () => {
    vi.useFakeTimers();
    try {
      const fetchImpl = vi.fn(
        (_url: RequestInfo | URL, init?: RequestInit) =>
          new Promise<Response>((_resolve, reject) => {
            init?.signal?.addEventListener("abort", () => {
              const err = new Error("aborted");
              err.name = "AbortError";
              reject(err);
            });
          }),
      );
      const pending = checkAppUpdate({ currentVersionName: "0.1.0", fetchImpl });
      await vi.advanceTimersByTimeAsync(8_000);
      const status = await pending;
      expect(status).toEqual({
        kind: "unavailable",
        currentVersion: "0.1.0",
        changelogUrl: DEFAULT_CHANGELOG_URL,
      });
    } finally {
      vi.useRealTimers();
    }
  });

  it("maps non-timeout abort to unavailable", async () => {
    const fetchImpl = vi.fn(async () => {
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    });
    const status = await checkAppUpdate({ currentVersionName: "0.1.0", fetchImpl });
    expect(status.kind).toBe("unavailable");
  });
});
