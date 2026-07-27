import { describe, expect, it } from "vitest";
import {
  sessionClient,
  setSessionTokensRefreshedHandler,
  setSessionUnauthorizedHandler,
} from "./sessionClient";

describe("sessionClient", () => {
  it("maps session fields onto ApiClientOptions", () => {
    const fetchImpl = async () => new Response();
    expect(
      sessionClient(
        {
          serverUrl: "https://prairie.example",
          accessToken: "tok",
          refreshToken: "ref",
          username: "ada",
          profileId: "p1",
          profileToken: "pin",
        },
        fetchImpl,
      ),
    ).toEqual({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      refreshToken: "ref",
      profileId: "p1",
      profileToken: "pin",
      fetchImpl,
      onUnauthorized: undefined,
      onTokensRefreshed: undefined,
    });
  });

  it("wires unauthorized and tokens-refreshed handlers", () => {
    const unauthorized = () => undefined;
    const refreshed = () => undefined;
    setSessionUnauthorizedHandler(unauthorized);
    setSessionTokensRefreshedHandler(refreshed);
    const options = sessionClient({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
    });
    expect(options.onUnauthorized).toBe(unauthorized);
    expect(options.onTokensRefreshed).toBe(refreshed);

    setSessionUnauthorizedHandler(undefined);
    setSessionTokensRefreshedHandler(undefined);
    const cleared = sessionClient({
      serverUrl: "https://prairie.example",
      accessToken: "tok",
      username: "ada",
      profileId: "p1",
    });
    expect(cleared.onUnauthorized).toBeUndefined();
    expect(cleared.onTokensRefreshed).toBeUndefined();
  });
});
