import { describe, expect, it } from "vitest";
import {
  compareAppVersions,
  formatAppVersion,
  parseAppVersion,
  type AppVersion,
} from "./appVersion";
import {
  changelogUrlOrNull,
  latestVersionLabel,
  releaseUrlOrNull,
  resolveAppUpdateStatus,
  statusLabel,
} from "./appUpdateStatus";

describe("parseAppVersion", () => {
  it("accepts v prefix and build metadata", () => {
    expect(parseAppVersion("v1.4.0")).toEqual({
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: false,
    });
    expect(parseAppVersion("1.4.0+2")).toEqual({
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: false,
    });
    expect(parseAppVersion("0.3.11")).toEqual({
      major: 0,
      minor: 3,
      patch: 11,
      prerelease: false,
    });
  });

  it("marks prerelease", () => {
    expect(parseAppVersion("v1.4.0-rc.1")).toEqual({
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: true,
    });
  });

  it("returns null for blank or unparseable input", () => {
    expect(parseAppVersion(null)).toBeNull();
    expect(parseAppVersion("")).toBeNull();
    expect(parseAppVersion("   ")).toBeNull();
    expect(parseAppVersion("1")).toBeNull();
    expect(parseAppVersion("not-a-version")).toBeNull();
  });

  it("defaults missing patch to 0", () => {
    expect(parseAppVersion("1.4")).toEqual({
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: false,
    });
  });
});

describe("compareAppVersions", () => {
  it("orders core then prerelease", () => {
    const a: AppVersion = { major: 1, minor: 4, patch: 1, prerelease: false };
    const b: AppVersion = { major: 1, minor: 4, patch: 0, prerelease: false };
    const pre: AppVersion = { major: 1, minor: 4, patch: 0, prerelease: true };
    expect(compareAppVersions(a, b)).toBeGreaterThan(0);
    expect(compareAppVersions(b, pre)).toBeGreaterThan(0);
    expect(compareAppVersions(b, b)).toBe(0);
    expect(formatAppVersion(a)).toBe("1.4.1");
  });
});

describe("resolveAppUpdateStatus", () => {
  it("reports update available when latest is newer", () => {
    const status = resolveAppUpdateStatus("0.3.11", "v1.4.0", "https://example.com/r");
    expect(status).toEqual({
      kind: "updateAvailable",
      currentVersion: "0.3.11",
      latestVersion: "1.4.0",
      releaseUrl: "https://example.com/r",
      changelogUrl: "https://example.com/r",
    });
    expect(statusLabel(status)).toBe("Update available");
    expect(latestVersionLabel(status)).toBe("1.4.0");
    expect(changelogUrlOrNull(status)).toBe("https://example.com/r");
    expect(releaseUrlOrNull(status)).toBe("https://example.com/r");
  });

  it("keeps changelog url when up to date", () => {
    const same = resolveAppUpdateStatus(
      "1.4.0",
      "v1.4.0",
      "https://example.com/r",
      "https://example.com/changelog",
    );
    expect(same.kind).toBe("upToDate");
    expect(statusLabel(same)).toBe("Up to date");
    expect(changelogUrlOrNull(same)).toBe("https://example.com/changelog");

    const olderLatest = resolveAppUpdateStatus("1.5.0", "1.4.0", null);
    expect(olderLatest.kind).toBe("upToDate");
  });

  it("returns unavailable on empty or unparseable latest", () => {
    expect(resolveAppUpdateStatus("1.0.0", null, null).kind).toBe("unavailable");
    expect(resolveAppUpdateStatus("1.0.0", "not-a-version", null).kind).toBe("unavailable");
    expect(latestVersionLabel(resolveAppUpdateStatus("1.0.0", null, null))).toBeNull();
    expect(releaseUrlOrNull(resolveAppUpdateStatus("1.0.0", null, null))).toBeNull();
    expect(
      changelogUrlOrNull(
        resolveAppUpdateStatus("1.0.0", null, null, "https://example.com/releases"),
      ),
    ).toBe("https://example.com/releases");
  });

  it("returns unavailable when current version is unparseable", () => {
    const status = resolveAppUpdateStatus("bogus", "1.0.0", null);
    expect(status.kind).toBe("unavailable");
    expect(statusLabel(status)).toBe("Couldn't check for updates");
  });

  it("labels checking status", () => {
    expect(statusLabel({ kind: "checking" })).toBe("Checking…");
    expect(latestVersionLabel({ kind: "checking" })).toBeNull();
    expect(changelogUrlOrNull({ kind: "checking" })).toBeNull();
  });
});
