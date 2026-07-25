import { describe, expect, it } from "vitest";
import { formatPlaybackClock } from "./timeFormat";

describe("formatPlaybackClock", () => {
  it("formats short and long clocks", () => {
    expect(formatPlaybackClock(0)).toBe("0:00");
    expect(formatPlaybackClock(65)).toBe("1:05");
    expect(formatPlaybackClock(3661)).toBe("1:01:01");
  });

  it("guards invalid values", () => {
    expect(formatPlaybackClock(Number.NaN)).toBe("0:00");
    expect(formatPlaybackClock(-3)).toBe("0:00");
  });
});
