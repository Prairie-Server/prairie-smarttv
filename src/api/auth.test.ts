import { describe, expect, it, vi } from "vitest";
import { listProfiles, login, pickDefaultProfile, verifyProfilePin } from "./auth";

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

  it("lists profiles and defaults missing arrays", async () => {
    const fetchImpl = vi.fn(async () => new Response("{}", { status: 200 }));
    await expect(listProfiles("https://prairie.example", "tok", fetchImpl)).resolves.toEqual([]);
  });

  it("verifies a profile PIN", async () => {
    const fetchImpl = vi.fn(async (url: RequestInfo | URL, init?: RequestInit) => {
      expect(String(url)).toContain("/api/v1/profiles/p1/verify-pin");
      expect(JSON.parse(String(init?.body))).toEqual({ pin: "1234" });
      return new Response(
        JSON.stringify({ valid: true, profile_token: "ptok" }),
        { status: 200 },
      );
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
