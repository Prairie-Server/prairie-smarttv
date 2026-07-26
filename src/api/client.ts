export class ApiError extends Error {
  status: number;
  code?: string;
  body?: unknown;

  constructor(message: string, status: number, code?: string, body?: unknown) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.body = body;
  }
}

export interface ApiClientOptions {
  serverUrl: string;
  accessToken?: string | null;
  /** Active household profile — required by most /api/v1 browse routes. */
  profileId?: string | null;
  /** PIN-verified profile token when the profile has a PIN. */
  profileToken?: string | null;
  fetchImpl?: typeof fetch;
  /** Request timeout in milliseconds. Defaults to 30s. */
  timeoutMs?: number;
  /**
   * Called when the server rejects the session (401, or 403 with auth codes).
   * Not invoked for auth/login so bad credentials do not recurse.
   */
  onUnauthorized?: () => void;
}

const DEFAULT_TIMEOUT_MS = 30_000;

/** 403 response codes that indicate the access token / session is no longer valid. */
const AUTH_FORBIDDEN_CODES = new Set([
  "unauthorized",
  "invalid_token",
  "token_expired",
  "authentication_required",
  "auth_required",
  "session_expired",
]);

function joinUrl(base: string, path: string): string {
  const normalizedBase = base.replace(/\/+$/, "");
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}

/** Paths that must not trigger onUnauthorized (bad login must not clear/loop). */
export function isAuthLoginPath(path: string): boolean {
  const bare = path.split("?")[0]?.replace(/\/+$/, "") ?? "";
  return bare === "/api/v1/auth/login" || bare.endsWith("/auth/login");
}

function shouldNotifyUnauthorized(status: number, code?: string): boolean {
  if (status === 401) return true;
  if (status === 403 && code && AUTH_FORBIDDEN_CODES.has(code)) return true;
  return false;
}

export async function apiRequest<T>(
  options: ApiClientOptions,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const headers = new Headers(init.headers);
  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }
  if (options.accessToken) {
    headers.set("Authorization", `Bearer ${options.accessToken}`);
  }
  if (options.profileId) {
    headers.set("X-Profile-Id", options.profileId);
  }
  if (options.profileToken) {
    headers.set("X-Profile-Token", options.profileToken);
  }
  headers.set("X-Prairie-Device-Platform", "smarttv");
  headers.set("X-Prairie-Device-Name", "Prairie Smart TV");

  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  let timedOut = false;
  const timeoutId = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);

  const onCallerAbort = () => controller.abort();
  if (init.signal) {
    if (init.signal.aborted) {
      controller.abort();
    } else {
      init.signal.addEventListener("abort", onCallerAbort, { once: true });
    }
  }

  let response: Response;
  try {
    response = await fetchImpl(joinUrl(options.serverUrl, path), {
      ...init,
      headers,
      signal: controller.signal,
    });
  } catch (err) {
    if (timedOut && err instanceof Error && err.name === "AbortError") {
      throw new ApiError("Request timed out", 408, "timeout");
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
    init.signal?.removeEventListener("abort", onCallerAbort);
  }

  if (!response.ok) {
    let body: unknown;
    let message = response.statusText || `HTTP ${response.status}`;
    let code: string | undefined;
    try {
      body = await response.json();
      if (body && typeof body === "object") {
        const record = body as Record<string, unknown>;
        if (typeof record.message === "string") message = record.message;
        else if (typeof record.error === "string") message = record.error;
        if (typeof record.code === "string") code = record.code;
      }
    } catch {
      /* ignore non-JSON */
    }
    if (
      options.onUnauthorized &&
      shouldNotifyUnauthorized(response.status, code) &&
      !isAuthLoginPath(path)
    ) {
      try {
        options.onUnauthorized();
      } catch {
        /* logout handlers must not mask the ApiError */
      }
    }
    throw new ApiError(message, response.status, code, body);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

/** True when `candidate` shares origin with the connected Prairie server. */
export function isSameServerOrigin(serverUrl: string, candidate: string): boolean {
  try {
    const server = new URL(serverUrl);
    const target = new URL(candidate, server);
    return target.protocol === server.protocol && target.host === server.host;
  } catch {
    return false;
  }
}

/**
 * Resolve a stream_url from Prairie against the server base and attach token
 * only when the resolved URL is same-origin with `serverUrl`. Cross-origin
 * absolute URLs (CDN, tuner, etc.) must not receive the session bearer.
 */
export function buildStreamUrl(
  serverUrl: string,
  streamPath: string,
  token: string | null,
): string {
  const base =
    streamPath.startsWith("http://") || streamPath.startsWith("https://")
      ? streamPath
      : joinUrl(serverUrl, streamPath);

  if (!token || !isSameServerOrigin(serverUrl, base)) return base;

  const params = new URLSearchParams();
  params.set("token", token);
  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}${params.toString()}`;
}
