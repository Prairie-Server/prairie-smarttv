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
    expect(parseAppVersion(undefined)).toBeNull();
    expect(parseAppVersion("")).toBeNull();
    expect(parseAppVersion("   ")).toBeNull();
    expect(parseAppVersion("1")).toBeNull();
    expect(parseAppVersion("not-a-version")).toBeNull();
    expect(parseAppVersion("x.y")).toBeNull();
    expect(parseAppVersion("1.x")).toBeNull();
  });

  it("defaults missing or unparseable patch to 0", () => {
    expect(parseAppVersion("1.4")).toEqual({
      major: 1,
      minor: 4,
      patch: 0,
      prerelease: false,
    });
    expect(parseAppVersion("2.0.abc")).toEqual({
      major: 2,
      minor: 0,
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
    const olderMajor: AppVersion = { major: 0, minor: 9, patch: 0, prerelease: false };
    const olderMinor: AppVersion = { major: 1, minor: 3, patch: 9, prerelease: false };
    expect(compareAppVersions(a, b)).toBeGreaterThan(0);
    expect(compareAppVersions(b, a)).toBeLessThan(0);
    expect(compareAppVersions(b, pre)).toBeGreaterThan(0);
    expect(compareAppVersions(pre, b)).toBeLessThan(0);
    expect(compareAppVersions(b, b)).toBe(0);
    expect(compareAppVersions(pre, pre)).toBe(0);
    expect(compareAppVersions(olderMajor, b)).toBeLessThan(0);
    expect(compareAppVersions(b, olderMajor)).toBeGreaterThan(0);
    expect(compareAppVersions(olderMinor, b)).toBeLessThan(0);
    expect(compareAppVersions(b, olderMinor)).toBeGreaterThan(0);
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

  it("returns unavailable when latest is blank after trim", () => {
    expect(resolveAppUpdateStatus("1.0.0", "   ", null).kind).toBe("unavailable");
  });

  it("falls back changelog to release url when resolving", () => {
    const status = resolveAppUpdateStatus("1.0.0", "1.1.0", "https://example.com/r", null);
    expect(status.kind).toBe("updateAvailable");
    if (status.kind === "updateAvailable") {
      expect(status.changelogUrl).toBe("https://example.com/r");
    }
  });

  it("labels checking status and reason overrides", () => {
    expect(statusLabel({ kind: "checking" })).toBe("Checking…");
    expect(latestVersionLabel({ kind: "checking" })).toBeNull();
    expect(changelogUrlOrNull({ kind: "checking" })).toBeNull();
    expect(
      statusLabel({
        kind: "unavailable",
        currentVersion: "1.0.0",
        reason: "Timed out",
      }),
    ).toBe("Timed out");
    expect(
      changelogUrlOrNull({
        kind: "updateAvailable",
        currentVersion: "1.0.0",
        latestVersion: "1.1.0",
        releaseUrl: "https://example.com/r",
        changelogUrl: null,
      }),
    ).toBe("https://example.com/r");
    expect(
      changelogUrlOrNull({
        kind: "upToDate",
        currentVersion: "1.0.0",
        latestVersion: "1.0.0",
      }),
    ).toBeNull();
    expect(
      changelogUrlOrNull({
        kind: "unavailable",
        currentVersion: "1.0.0",
      }),
    ).toBeNull();
  });
});
