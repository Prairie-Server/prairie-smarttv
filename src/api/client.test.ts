import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ApiError,
  apiRequest,
  buildStreamUrl,
  isAuthLoginPath,
  isSameServerOrigin,
} from "./client";

describe("buildStreamUrl", () => {
  it("joins relative stream paths and appends token", () => {
    expect(buildStreamUrl("https://prairie.example", "/api/v1/stream/abc", "tok")).toBe(
      "https://prairie.example/api/v1/stream/abc?token=tok",
    );
  });

  it("appends token to same-origin absolute URLs with existing query params", () => {
    expect(buildStreamUrl("https://prairie.example", "https://prairie.example/s?st=1", "tok")).toBe(
      "https://prairie.example/s?st=1&token=tok",
    );
  });

  it("does not attach the session token to cross-origin absolute URLs", () => {
    expect(buildStreamUrl("https://prairie.example", "https://cdn.example/s?st=1", "tok")).toBe(
      "https://cdn.example/s?st=1",
    );
  });

  it("appends profile_id for same-origin streams when provided", () => {
    expect(
      buildStreamUrl(
        "https://prairie.example",
        "/api/v1/livetv/live-hls/t/index.m3u8",
        "tok",
        "p1",
      ),
    ).toBe("https://prairie.example/api/v1/livetv/live-hls/t/index.m3u8?token=tok&profile_id=p1");
    expect(
      buildStreamUrl(
        "https://prairie.example",
        "https://prairie.example/live.m3u8?st=1",
        "tok",
        "p1",
      ),
    ).toBe("https://prairie.example/live.m3u8?st=1&token=tok&profile_id=p1");
    expect(buildStreamUrl("https://prairie.example", "/live.m3u8", null, "p1")).toBe(
      "https://prairie.example/live.m3u8?profile_id=p1",
    );
  });
});

describe("isAuthLoginPath", () => {
  it("matches login routes with optional query/trailing slash", () => {
    expect(isAuthLoginPath("/api/v1/auth/login")).toBe(true);
    expect(isAuthLoginPath("/api/v1/auth/login?x=1")).toBe(true);
    expect(isAuthLoginPath("/api/v1/auth/login/")).toBe(true);
    expect(isAuthLoginPath("/api/v1/home/sections")).toBe(false);
  });
});

describe("apiRequest", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("parses error bodies into ApiError", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "bad creds", code: "auth_failed" }), {
          status: 401,
          statusText: "Unauthorized",
        }),
    );

    await expect(
      apiRequest({ serverUrl: "https://prairie.example", fetchImpl }, "/api/v1/auth/login", {
        method: "POST",
        body: "{}",
      }),
    ).rejects.toMatchObject({
      name: "ApiError",
      message: "bad creds",
      status: 401,
      code: "auth_failed",
    } satisfies Partial<ApiError>);
  });

  it("calls onUnauthorized for 401 on non-login paths", async () => {
    const onUnauthorized = vi.fn();
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "expired" }), {
          status: 401,
          statusText: "Unauthorized",
        }),
    );

    await expect(
      apiRequest(
        { serverUrl: "https://prairie.example", fetchImpl, onUnauthorized },
        "/api/v1/home/sections",
      ),
    ).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("does not call onUnauthorized for auth/login 401", async () => {
    const onUnauthorized = vi.fn();
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "bad creds" }), {
          status: 401,
          statusText: "Unauthorized",
        }),
    );

    await expect(
      apiRequest(
        { serverUrl: "https://prairie.example", fetchImpl, onUnauthorized },
        "/api/v1/auth/login",
        { method: "POST", body: "{}" },
      ),
    ).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  it("calls onUnauthorized for 403 with auth codes", async () => {
    const onUnauthorized = vi.fn();
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "gone", code: "token_expired" }), {
          status: 403,
          statusText: "Forbidden",
        }),
    );

    await expect(
      apiRequest(
        { serverUrl: "https://prairie.example", fetchImpl, onUnauthorized },
        "/api/v1/libraries",
      ),
    ).rejects.toMatchObject({ status: 403, code: "token_expired" });
    expect(onUnauthorized).toHaveBeenCalledOnce();
  });

  it("does not call onUnauthorized for ordinary 403", async () => {
    const onUnauthorized = vi.fn();
    const fetchImpl = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "nope" }), {
          status: 403,
          statusText: "Forbidden",
        }),
    );

    await expect(
      apiRequest(
        { serverUrl: "https://prairie.example", fetchImpl, onUnauthorized },
        "/api/v1/libraries",
      ),
    ).rejects.toMatchObject({ status: 403 });
    expect(onUnauthorized).not.toHaveBeenCalled();
  });

  it("aborts hung requests after the timeout", async () => {
    vi.useFakeTimers();
    const fetchImpl = vi.fn(
      (_url: RequestInfo | URL, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            const err = new Error("Aborted");
            err.name = "AbortError";
            reject(err);
          });
        }),
    );

    const pending = apiRequest(
      { serverUrl: "https://prairie.example", fetchImpl, timeoutMs: 30_000 },
      "/api/v1/profiles",
    );

    const expectation = expect(pending).rejects.toMatchObject({
      name: "ApiError",
      message: "Request timed out",
      status: 408,
      code: "timeout",
    });

    await vi.advanceTimersByTimeAsync(30_000);
    await expectation;
  });

  it("sends profile headers when provided", async () => {
    const fetchImpl = vi.fn(async (_url: RequestInfo | URL, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      expect(headers.get("X-Profile-Id")).toBe("profile-1");
      expect(headers.get("X-Profile-Token")).toBe("pin-token");
      return new Response("{}", { status: 200 });
    });

    await apiRequest(
      {
        serverUrl: "https://prairie.example",
        accessToken: "tok",
        profileId: "profile-1",
        profileToken: "pin-token",
        fetchImpl,
      },
      "/api/v1/home/sections",
    );
    expect(fetchImpl).toHaveBeenCalledOnce();
  });

  it("preserves caller AbortError instead of reporting a timeout", async () => {
    const caller = new AbortController();
    const fetchImpl = vi.fn(
      (_url: RequestInfo | URL, init?: RequestInit) =>
        new Promise<Response>((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => {
            const err = new Error("Aborted");
            err.name = "AbortError";
            reject(err);
          });
        }),
    );

    const pending = apiRequest(
      { serverUrl: "https://prairie.example", fetchImpl, timeoutMs: 30_000 },
      "/api/v1/profiles",
      { signal: caller.signal },
    );

    const expectation = expect(pending).rejects.toMatchObject({
      name: "AbortError",
    });
    caller.abort();
    await expectation;
  });

  it("covers error body fallbacks and same-origin helpers", async () => {
    expect(isSameServerOrigin("https://prairie.example", "https://prairie.example/x")).toBe(true);
    expect(isSameServerOrigin("https://prairie.example", "https://other.example/x")).toBe(false);
    expect(isSameServerOrigin(":::", "https://x")).toBe(false);

    const errorField = vi.fn(
      async () =>
        new Response(JSON.stringify({ error: "nope" }), {
          status: 500,
          statusText: "",
        }),
    );
    await expect(
      apiRequest({ serverUrl: "https://prairie.example", fetchImpl: errorField }, "/api/v1/x"),
    ).rejects.toMatchObject({ message: "nope", status: 500 });

    const nonJson = vi.fn(async () => new Response("plain", { status: 502, statusText: "Bad" }));
    await expect(
      apiRequest({ serverUrl: "https://prairie.example", fetchImpl: nonJson }, "/api/v1/x"),
    ).rejects.toMatchObject({ message: "Bad", status: 502 });

    const onUnauthorized = vi.fn(() => {
      throw new Error("handler boom");
    });
    const unauthorized = vi.fn(
      async () =>
        new Response(JSON.stringify({ message: "expired" }), {
          status: 401,
          statusText: "Unauthorized",
        }),
    );
    await expect(
      apiRequest(
        { serverUrl: "https://prairie.example", fetchImpl: unauthorized, onUnauthorized },
        "/api/v1/home",
      ),
    ).rejects.toMatchObject({ status: 401 });
    expect(onUnauthorized).toHaveBeenCalledOnce();

    const empty = vi.fn(async () => new Response(null, { status: 204 }));
    await expect(
      apiRequest({ serverUrl: "https://prairie.example", fetchImpl: empty }, "/api/v1/x"),
    ).resolves.toBeUndefined();

    expect(buildStreamUrl("https://prairie.example", "/stream", null)).toBe(
      "https://prairie.example/stream",
    );
  });
});
