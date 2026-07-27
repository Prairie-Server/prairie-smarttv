import { describe, expect, it } from "vitest";
import {
  normalizeResolution,
  resolveTargetResolution,
  targetBitrateKbpsForResolution,
} from "./targetResolution";

describe("normalizeResolution", () => {
  it("maps common aliases to Prairie tokens", () => {
    expect(normalizeResolution("2160p")).toBe("2160p");
    expect(normalizeResolution("4K")).toBe("2160p");
    expect(normalizeResolution("uhd")).toBe("2160p");
    expect(normalizeResolution("3840x2160")).toBe("2160p");
    expect(normalizeResolution("1440p")).toBe("1440p");
    expect(normalizeResolution("2560x1440")).toBe("1440p");
    expect(normalizeResolution("1920x1080")).toBe("1080p");
    expect(normalizeResolution("720p")).toBe("720p");
    expect(normalizeResolution("1280x720")).toBe("720p");
    expect(normalizeResolution("480p")).toBe("480p");
    expect(normalizeResolution("420p")).toBe("420p");
    expect(normalizeResolution("360p")).toBe("360p");
    expect(normalizeResolution("")).toBe("");
    expect(normalizeResolution("mystery")).toBe("");
  });

  it("infers height from trailing digit tokens", () => {
    expect(normalizeResolution("2160")).toBe("2160p");
    expect(normalizeResolution("1500")).toBe("1440p");
    expect(normalizeResolution("900")).toBe("720p");
    expect(normalizeResolution("500")).toBe("480p");
    expect(normalizeResolution("240")).toBe("360p");
  });
});

describe("resolveTargetResolution", () => {
  it("keeps 4K when the panel is 4K", () => {
    expect(resolveTargetResolution("2160p", "2160p")).toBe("2160p");
  });

  it("caps a 4K source to a 1080p panel", () => {
    expect(resolveTargetResolution("2160p", "1080p")).toBe("1080p");
  });

  it("does not upscale a 720p source on a 4K panel", () => {
    expect(resolveTargetResolution("720p", "2160p")).toBe("720p");
  });

  it("falls back to the device max when the source is unknown", () => {
    expect(resolveTargetResolution(null, "2160p")).toBe("2160p");
    expect(resolveTargetResolution(undefined, undefined)).toBe("1080p");
  });
});

describe("targetBitrateKbpsForResolution", () => {
  it("scales bitrate with resolution", () => {
    expect(targetBitrateKbpsForResolution("2160p")).toBe(20_000);
    expect(targetBitrateKbpsForResolution("1440p")).toBe(12_000);
    expect(targetBitrateKbpsForResolution("1080p")).toBe(6_000);
    expect(targetBitrateKbpsForResolution("720p")).toBe(3_000);
    expect(targetBitrateKbpsForResolution("480p")).toBe(1_500);
    expect(targetBitrateKbpsForResolution("weird")).toBe(6_000);
  });
});
