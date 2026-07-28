import { describe, expect, it } from "vitest";
import { toMediaTime, toPlayerTime } from "./mediaTimeline";

describe("toMediaTime / toPlayerTime", () => {
  it("maps a windowed resume timeline", () => {
    expect(toMediaTime(0, 456)).toBe(456);
    expect(toMediaTime(15, 456)).toBe(471);
    expect(toPlayerTime(471, 456)).toBe(15);
  });

  it("preserves an out-of-window target before the stream origin", () => {
    expect(toPlayerTime(440, 456)).toBe(-16);
    expect(toMediaTime(0, 0)).toBe(0);
  });
});
