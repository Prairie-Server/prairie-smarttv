/**
 * Marketing semver used for client update checks.
 *
 * Tags may look like `v1.4.0`, `1.4.0+2`, or `v1.4.0-rc.1`. Only the
 * `major.minor.patch` core is compared; prerelease tags sort below the
 * matching release, and a missing/unparseable version is treated as older.
 */
export interface AppVersion {
  major: number;
  minor: number;
  patch: number;
  prerelease: boolean;
}

export function parseAppVersion(raw: string | null | undefined): AppVersion | null {
  if (raw == null || raw.trim() === "") return null;
  let text = raw.trim();
  if (text.toLowerCase().startsWith("v")) {
    text = text.slice(1);
  }
  // Drop build metadata (`+2`) before detecting prerelease.
  const withoutBuild = text.split("+", 1)[0] ?? text;
  const prerelease = withoutBuild.includes("-");
  const core = withoutBuild.split("-", 1)[0] ?? withoutBuild;
  const parts = core.split(".");
  if (parts.length < 2) return null;
  const major = Number.parseInt(parts[0] ?? "", 10);
  const minor = Number.parseInt(parts[1] ?? "", 10);
  if (!Number.isFinite(major) || !Number.isFinite(minor)) return null;
  // Missing or unparseable patch defaults to 0 (Android AppVersion parity).
  const patchParsed = parts[2] == null ? NaN : Number.parseInt(parts[2], 10);
  const patch = Number.isFinite(patchParsed) ? patchParsed : 0;
  return { major, minor, patch, prerelease };
}

export function compareAppVersions(a: AppVersion, b: AppVersion): number {
  if (a.major !== b.major) return a.major < b.major ? -1 : 1;
  if (a.minor !== b.minor) return a.minor < b.minor ? -1 : 1;
  if (a.patch !== b.patch) return a.patch < b.patch ? -1 : 1;
  if (a.prerelease === b.prerelease) return 0;
  return a.prerelease ? -1 : 1;
}

export function formatAppVersion(version: AppVersion): string {
  return `${version.major}.${version.minor}.${version.patch}`;
}
