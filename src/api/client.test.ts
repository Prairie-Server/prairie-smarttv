import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, apiRequest, buildStreamUrl } from "./client";

describe("buildStreamUrl", () => {
  it("joins relative stream paths and appends token", () => {
    expect(buildStreamUrl("https://prairie.example", "/api/v1/stream/abc", "tok")).toBe(
      "https://prairie.example/api/v1/stream/abc?token=tok",
    );
  });

  it("preserves existing query params", () => {
    expect(
      buildStreamUrl("https://prairie.example", "https://cdn.example/s?st=1", "tok"),
    ).toBe("https://cdn.example/s?st=1&token=tok");
  });
});

describe("apiRequest", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it("parses error bodies into ApiError", async () => {
    const fetchImpl = vi.fn(async () =>
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
});
