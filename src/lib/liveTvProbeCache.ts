/**
 * Persists whether the connected server has Live TV channels so Home can
 * reserve the On now row on the next launch instead of inserting it late.
 */

const STORAGE_PREFIX = "prairie.liveTvAvailable:";

export function loadCachedLiveTvAvailable(serverUrl: string): boolean | null {
  const key = `${STORAGE_PREFIX}${serverUrl.trim()}`;
  try {
    if (typeof localStorage === "undefined") return null;
    const raw = localStorage.getItem(key);
    if (raw === "1") return true;
    if (raw === "0") return false;
  } catch {
    // Private mode / quota — treat as unknown.
  }
  return null;
}

export function saveCachedLiveTvAvailable(serverUrl: string, available: boolean): void {
  const key = `${STORAGE_PREFIX}${serverUrl.trim()}`;
  try {
    if (typeof localStorage === "undefined") return;
    localStorage.setItem(key, available ? "1" : "0");
  } catch {
    // Ignore persistence failures.
  }
}
