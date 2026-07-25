import { describe, expect, it } from "vitest";
import { buildStreamUrl } from "./client";

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
