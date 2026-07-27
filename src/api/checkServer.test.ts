import { describe, expect, it, vi } from "vitest";
import {
  buildManualUrlCandidates,
  checkServer,
  checkServerCandidates,
  networkFailureMessage,
} from "./checkServer";
import { ApiError } from "./client";

describe("buildManualUrlCandidates", () => {
  it("keeps an explicit scheme without fallback", () => {
    expect(buildManualUrlCandidates(" https://prairie.example/ ")).toEqual([
      "https://prairie.example",
    ]);
    expect(buildManualUrlCandidates("HTTP://192.168.1.10:8080/")).toEqual([
      "http://192.168.1.10:8080",
    ]);
  });

  it("tries https then http for bare hosts", () => {
    expect(buildManualUrlCandidates("prairie.local:8080")).toEqual([
      "https://prairie.local:8080",
      "http://prairie.local:8080",
    ]);
  });

  it("returns empty for blank input", () => {
    expect(buildManualUrlCandidates("   ")).toEqual([]);
  });
});

describe("networkFailureMessage", () => {
  it("maps browser fetch failures to a helpful message", () => {
    expect(networkFailureMessage(new TypeError("Failed to fetch"))).toMatch(/http vs https/i);
  });

  it("maps timeouts", () => {
    expect(networkFailureMessage(new ApiError("Request timed out", 408, "timeout"))).toMatch(
      /timed out/i,
    );
  });

  it("maps ApiError bodies when message is missing/blank", () => {
    expect(networkFailureMessage(new ApiError("   ", 500))).toMatch(/Could not reach/i);
  });

  it("maps non-TypeError Error messages via regex", () => {
    expect(networkFailureMessage(new Error("network request failed"))).toMatch(/Could not reach/i);
  });

  it("passes through non-matching Error messages", () => {
    expect(networkFailureMessage(new Error("Something else"))).toBe("Something else");
  });

  it("falls back on unknown error types", () => {
    expect(networkFailureMessage(null)).toMatch(/Could not reach/i);
  });
});

describe("checkServer", () => {
  it("returns needsSetup from /auth/setup and optional health name", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const href = String(url);
      if (href.includes("/api/v1/auth/setup")) {
        return new Response(JSON.stringify({ needs_setup: false }), { status: 200 });
      }
      if (href.includes("/api/v1/health")) {
        return new Response(
          JSON.stringify({ status: "ok", server_name: "Den", server_id: "abc" }),
          { status: 200 },
        );
      }
      return new Response("missing", { status: 404 });
    });

    await expect(checkServer("https://prairie.example", { fetchImpl })).resolves.toEqual({
      ok: true,
      serverUrl: "https://prairie.example",
      needsSetup: false,
      serverName: "Den",
    });
  });

  it("fails closed when setup cannot be reached", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("Failed to fetch");
    });

    const result = await checkServer("https://wrong-scheme.example:8080", { fetchImpl });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.message).toMatch(/Could not reach/i);
    }
  });

  it("rejects blank input", async () => {
    const result = await checkServer("   ", { fetchImpl: vi.fn() });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.message).toMatch(/valid Prairie server address/i);
  });

  it("rejects invalid URL and non-http(s) protocols", async () => {
    await expect(checkServer("not-a-url", { fetchImpl: vi.fn() })).resolves.toMatchObject({
      ok: false,
    });
    await expect(checkServer("ftp://example.com", { fetchImpl: vi.fn() })).resolves.toMatchObject({
      ok: false,
    });
  });

  it("rejects URLs with embedded credentials", async () => {
    const result = await checkServer("http://user:pass@example.com", { fetchImpl: vi.fn() });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.message).toMatch(/credentials/i);
  });

  it("propagates needsSetup=true and handles missing/failed health name", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const href = String(url);
      if (href.includes("/api/v1/auth/setup")) {
        return new Response(JSON.stringify({ needs_setup: true }), { status: 200 });
      }
      if (href.includes("/api/v1/health")) {
        // Health is optional; simulate it failing so serverName stays undefined.
        throw new Error("health failed");
      }
      return new Response("missing", { status: 404 });
    });

    const result = await checkServer("https://prairie.example", { fetchImpl });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.needsSetup).toBe(true);
      expect(result.serverName).toBeUndefined();
    }
  });
});

describe("checkServerCandidates", () => {
  it("falls back to http when https fails for bare hosts", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      const href = String(url);
      if (href.startsWith("https://")) {
        throw new TypeError("Failed to fetch");
      }
      if (href.includes("/api/v1/auth/setup")) {
        return new Response(JSON.stringify({ needs_setup: true }), { status: 200 });
      }
      if (href.includes("/api/v1/health")) {
        return new Response(JSON.stringify({ status: "ok" }), { status: 200 });
      }
      return new Response("missing", { status: 404 });
    });

    const result = await checkServerCandidates(buildManualUrlCandidates("192.168.1.10:8080"), {
      fetchImpl,
    });
    expect(result).toEqual({
      ok: true,
      serverUrl: "http://192.168.1.10:8080",
      needsSetup: true,
      serverName: undefined,
    });
  });

  it("returns an error when candidates is empty", async () => {
    const result = await checkServerCandidates([], { fetchImpl: vi.fn() });
    expect(result.ok).toBe(false);
  });

  it("returns the last failure when all candidates fail", async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError("Failed to fetch");
    });

    const result = await checkServerCandidates(["https://a", "http://b"], { fetchImpl });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.message).toMatch(/Could not reach/i);
    }
  });
});
