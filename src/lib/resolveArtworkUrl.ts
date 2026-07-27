/**
 * Resolve artwork / media paths against the connected Prairie origin.
 * Packaged Tizen/webOS apps are not same-origin with the server, so relative
 * `/artwork/...` URLs must be absolutized or `<img>` hits the widget origin.
 */

export function joinServerUrl(serverUrl: string, path: string): string {
  const base = serverUrl.replace(/\/+$/, "");
  if (!path) return base;
  if (path.startsWith("http://") || path.startsWith("https://") || path.startsWith("data:")) {
    return path;
  }
  if (path.startsWith("//")) {
    try {
      return `${new URL(base).protocol}${path}`;
    } catch {
      return `https:${path}`;
    }
  }
  return `${base}${path.startsWith("/") ? path : `/${path}`}`;
}

/** Absolutize a poster/backdrop/still URL when a server origin is known. */
export function resolveArtworkUrl(
  objectPath: string | null | undefined,
  serverUrl: string | null | undefined,
): string {
  const trimmed = objectPath?.trim() ?? "";
  if (!trimmed) return "";
  const base = serverUrl?.trim() ?? "";
  if (!base) return trimmed;
  return joinServerUrl(base, trimmed);
}
