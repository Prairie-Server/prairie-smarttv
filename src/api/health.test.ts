import { describe, expect, it, vi } from "vitest";
import { fetchServerHealth } from "./health";

describe("fetchServerHealth", () => {
  it("returns parsed identity on ok health", async () => {
    const fetchImpl = vi.fn(async () =>
      Response.json({ status: "ok", server_name: "Den", server_id: "1" }),
    ) as unknown as typeof fetch;
    await expect(fetchServerHealth("https://prairie.example", fetchImpl)).resolves.toEqual({
      serverName: "Den",
      serverId: "1",
    });
  });

  it("returns null on failure", async () => {
    const fetchImpl = vi.fn(
      async () => new Response("no", { status: 500 }),
    ) as unknown as typeof fetch;
    await expect(fetchServerHealth("https://prairie.example", fetchImpl)).resolves.toBeNull();
  });
});
