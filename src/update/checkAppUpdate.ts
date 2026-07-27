import { resolveAppUpdateStatus, type AppUpdateStatus } from "./appUpdateStatus";

export const DEFAULT_RELEASES_LATEST_URL =
  "https://api.github.com/repos/Prairie-Server/prairie-smarttv/releases/latest";

export const DEFAULT_CHANGELOG_URL = "https://github.com/Prairie-Server/prairie-smarttv/releases";

const TIMEOUT_MS = 8_000;

interface GitHubLatestRelease {
  tag_name?: string | null;
  name?: string | null;
  html_url?: string | null;
}

export interface CheckAppUpdateOptions {
  currentVersionName: string;
  fetchImpl?: typeof fetch;
  releasesLatestUrl?: string;
}

/**
 * Checks GitHub Releases for a newer Prairie Smart TV build.
 * Uses an absolute GitHub URL so Prairie server credentials never leave the app.
 */
export async function checkAppUpdate(options: CheckAppUpdateOptions): Promise<AppUpdateStatus> {
  const {
    currentVersionName,
    fetchImpl = fetch,
    releasesLatestUrl = DEFAULT_RELEASES_LATEST_URL,
  } = options;

  const controller = new AbortController();
  let timedOut = false;
  const timeoutId = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, TIMEOUT_MS);

  try {
    const response = await fetchImpl(releasesLatestUrl, {
      method: "GET",
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "Prairie-SmartTV",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      signal: controller.signal,
    });

    // No published releases yet → treat as up to date rather than an error.
    if (response.status === 404) {
      return {
        kind: "upToDate",
        currentVersion: currentVersionName,
        latestVersion: currentVersionName,
        changelogUrl: DEFAULT_CHANGELOG_URL,
      };
    }

    if (!response.ok) {
      return {
        kind: "unavailable",
        currentVersion: currentVersionName,
        changelogUrl: DEFAULT_CHANGELOG_URL,
      };
    }

    const release = (await response.json()) as GitHubLatestRelease;
    const releaseUrl = typeof release.html_url === "string" ? release.html_url : null;
    return resolveAppUpdateStatus(
      currentVersionName,
      release.tag_name ?? release.name,
      releaseUrl,
      releaseUrl ?? DEFAULT_CHANGELOG_URL,
    );
  } catch (err) {
    if (timedOut && err instanceof Error && err.name === "AbortError") {
      return {
        kind: "unavailable",
        currentVersion: currentVersionName,
        changelogUrl: DEFAULT_CHANGELOG_URL,
      };
    }
    return {
      kind: "unavailable",
      currentVersion: currentVersionName,
      changelogUrl: DEFAULT_CHANGELOG_URL,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}
