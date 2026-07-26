import { describe, expect, it } from "vitest";
import { sessionClient } from "./sessionClient";

describe("sessionClient", () => {
  it("maps session fields onto ApiClientOptions", () => {
    const fetchImpl = async () => new Response();
    expect(
      sessionClient(
        {
          serverUrl: "https://prairie.example",
          accessToken: "tok",
          username: "ada",
          profileId: "p1",
          profileToken: "pin",
        },
        fetchImpl,
      ),
    ).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      profileId: "p1",
      profileToken: "pin",
      fetchImpl,
      onUnauthorized: undefined,
    });
  });
});
