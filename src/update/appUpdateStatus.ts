import { compareAppVersions, formatAppVersion, parseAppVersion } from "./appVersion";

/**
 * Result of comparing the installed client version against the latest
 * published GitHub release for this app family.
 */
export type AppUpdateStatus =
  | { kind: "checking" }
  | {
      kind: "upToDate";
      currentVersion: string;
      latestVersion: string;
      changelogUrl?: string | null;
    }
  | {
      kind: "updateAvailable";
      currentVersion: string;
      latestVersion: string;
      releaseUrl: string | null;
      changelogUrl?: string | null;
    }
  | {
      kind: "unavailable";
      currentVersion: string;
      reason?: string;
      changelogUrl?: string | null;
    };

export function statusLabel(status: AppUpdateStatus): string {
  switch (status.kind) {
    case "checking":
      return "Checking…";
    case "upToDate":
      return "Up to date";
    case "updateAvailable":
      return "Update available";
    case "unavailable":
      return status.reason ?? "Couldn't check for updates";
  }
}

export function latestVersionLabel(status: AppUpdateStatus): string | null {
  switch (status.kind) {
    case "checking":
    case "unavailable":
      return null;
    case "upToDate":
    case "updateAvailable":
      return status.latestVersion;
  }
}

export function releaseUrlOrNull(status: AppUpdateStatus): string | null {
  return status.kind === "updateAvailable" ? status.releaseUrl : null;
}

export function changelogUrlOrNull(status: AppUpdateStatus): string | null {
  switch (status.kind) {
    case "checking":
      return null;
    case "upToDate":
      return status.changelogUrl ?? null;
    case "updateAvailable":
      return status.changelogUrl ?? status.releaseUrl ?? null;
    case "unavailable":
      return status.changelogUrl ?? null;
  }
}

/**
 * Resolve a status from the installed marketing version and a latest release
 * tag / display version. Pure so unit tests cover the decision table without
 * hitting the network.
 */
export function resolveAppUpdateStatus(
  currentVersionName: string,
  latestVersionName: string | null | undefined,
  releaseUrl: string | null,
  changelogUrl: string | null = releaseUrl,
): AppUpdateStatus {
  const current = parseAppVersion(currentVersionName);
  if (!current) {
    return {
      kind: "unavailable",
      currentVersion: currentVersionName,
      changelogUrl,
    };
  }
  const latestRaw = latestVersionName?.trim() ?? "";
  if (latestRaw === "") {
    return {
      kind: "unavailable",
      currentVersion: currentVersionName,
      changelogUrl,
    };
  }
  const latest = parseAppVersion(latestRaw);
  if (!latest) {
    return {
      kind: "unavailable",
      currentVersion: currentVersionName,
      changelogUrl,
    };
  }
  const latestDisplay = formatAppVersion(latest);
  const notesUrl = changelogUrl ?? releaseUrl;
  if (compareAppVersions(latest, current) > 0) {
    return {
      kind: "updateAvailable",
      currentVersion: currentVersionName,
      latestVersion: latestDisplay,
      releaseUrl,
      changelogUrl: notesUrl,
    };
  }
  return {
    kind: "upToDate",
    currentVersion: currentVersionName,
    latestVersion: latestDisplay,
    changelogUrl: notesUrl,
  };
}
