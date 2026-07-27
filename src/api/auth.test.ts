import { describe, expect, it, vi } from "vitest";
import {
  fetchSetupStatus,
  listProfiles,
  login,
  pickDefaultProfile,
  pollDeviceLogin,
  startDeviceLogin,
  verifyProfilePin,
} from "./auth";

describe("pickDefaultProfile", () => {
  it("returns null for an empty list", () => {
    expect(pickDefaultProfile([])).toBeNull();
  });

  it("prefers the primary profile", () => {
    expect(
      pickDefaultProfile([
        { id: "a", name: "A", is_primary: false, is_child: false },
        { id: "b", name: "B", is_primary: true, is_child: false },
      ])?.id,
    ).toBe("b");
  });

  it("falls back to the first profile", () => {
    expect(
      pickDefaultProfile([
        { id: "a", name: "A", is_primary: false, is_child: false },
        { id: "b", name: "B", is_primary: false, is_child: true },
      ])?.id,
    ).toBe("a");
  });
});

describe("auth API helpers", () => {
  it("fetches setup status", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL) => {
      expect(String(url)).toContain("/api/v1/auth/setup");
      return new Response(JSON.stringify({ needs_setup: true }), { status: 200 });
    });

    const result = await fetchSetupStatus("https://prairie.example", fetchImpl);
    expect(result.needs_setup).toBe(true);
  });

  it("posts login credentials", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/auth/login");
      expect(init?.method).toBe("POST");
      expect(JSON.parse(String(init?.body))).toEqual({ username: "ada", password: "secret" });
      return new Response(
        JSON.stringify({
          access_token: "a",
          refresh_token: "r",
          expires_in: 3600,
          user: { id: 1, username: "ada" },
        }),
        { status: 200 },
      );
    });

    const result = await login(
      "https://prairie.example",
      { username: "ada", password: "secret" },
      fetchImpl,
    );
    expect(result.access_token).toBe("a");
    expect(result.user.username).toBe("ada");
  });

  it("starts and polls device login", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      const href = String(url);
      if (href.includes("/auth/device/start")) {
        expect(init?.method).toBe("POST");
        return new Response(
          JSON.stringify({
            device_code: "secret",
            user_code: "ABCD-EFGH",
            match_code: "amber harbor",
            verification_uri: "https://prairie.example/activate",
            verification_uri_complete: "https://prairie.example/activate?token=t",
            expires_at: "2026-07-27T00:00:00Z",
            expires_in: 600,
            interval: 3,
            device_name: "Prairie Smart TV",
            device_platform: "tizen",
          }),
          { status: 201 },
        );
      }
      expect(href).toContain("/auth/device/poll");
      expect(JSON.parse(String(init?.body))).toEqual({ device_code: "secret" });
      return new Response(JSON.stringify({ status: "pending", poll_after: 3 }), { status: 200 });
    });

    const start = await startDeviceLogin(
      "https://prairie.example",
      { device_name: "Prairie Smart TV", device_platform: "tizen" },
      fetchImpl,
    );
    expect(start.user_code).toBe("ABCD-EFGH");
    const poll = await pollDeviceLogin("https://prairie.example", "secret", fetchImpl);
    expect(poll.status).toBe("pending");
  });

  it("lists profiles and defaults missing arrays", async () => {
    const fetchImpl = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(listProfiles("https://prairie.example", "tok", fetchImpl)).resolves.toEqual([]);
  });

  it("returns profile arrays from the server", async () => {
    const fetchImpl = vi.fn(
      async () =>
        new Response(
          JSON.stringify({
            profiles: [{ id: "p1", name: "Primary", is_primary: true, is_child: false }],
          }),
          { status: 200 },
        ),
    );
    await expect(listProfiles("https://prairie.example", "tok", fetchImpl)).resolves.toEqual([
      { id: "p1", name: "Primary", is_primary: true, is_child: false },
    ]);
  });

  it("verifies a profile PIN", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/profiles/p1/verify-pin");
      expect(JSON.parse(String(init?.body))).toEqual({ pin: "1234" });
      return new Response(JSON.stringify({ valid: true, profile_token: "ptok" }), { status: 200 });
    });

    const result = await verifyProfilePin(
      "https://prairie.example",
      "tok",
      "p1",
      "1234",
      fetchImpl,
    );
    expect(result).toEqual({ valid: true, profile_token: "ptok" });
  });
});
