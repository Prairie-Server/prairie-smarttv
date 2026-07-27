import { imageFormatsHeaderValue } from "../lib/imageFormats";
import { refreshAccessToken } from "./auth";
import { ACCESS_TOKEN_KEY, REFRESH_TOKEN_KEY, updateSessionTokens } from "../storage/session";

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
  refreshToken?: string | null;
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
   * Also skipped when a refresh token successfully renews the session.
   */
  onUnauthorized?: () => void;
  /** Fired after a successful access-token refresh so React state can catch up. */
  onTokensRefreshed?: (tokens: { accessToken: string; refreshToken?: string }) => void;
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

/** Single-flight refresh so concurrent 401s share one round-trip. */
let refreshInFlight: Promise<boolean> | null = null;

function joinUrl(base: string, path: string): string {
  const normalizedBase = base.replace(/\/+$/, "");
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
}

/** Paths that must not trigger onUnauthorized (bad login must not clear/loop). */
export function isAuthLoginPath(path: string): boolean {
  const bare = path.split("?")[0]?.replace(/\/+$/, "") ?? "";
  return (
    bare === "/api/v1/auth/login" ||
    bare.endsWith("/auth/login") ||
    bare === "/api/v1/auth/refresh" ||
    bare.endsWith("/auth/refresh")
  );
}

function shouldNotifyUnauthorized(status: number, code?: string): boolean {
  if (status === 401) return true;
  if (status === 403 && code && AUTH_FORBIDDEN_CODES.has(code)) return true;
  return false;
}

function readRefreshToken(options: ApiClientOptions): string | null {
  if (options.refreshToken) return options.refreshToken;
  try {
    return localStorage.getItem(REFRESH_TOKEN_KEY);
  } catch {
    return null;
  }
}

async function tryRefreshSession(options: ApiClientOptions): Promise<boolean> {
  const refreshToken = readRefreshToken(options);
  if (!refreshToken) return false;

  if (!refreshInFlight) {
    refreshInFlight = (async () => {
      try {
        const pair = await refreshAccessToken(options.serverUrl, refreshToken, options.fetchImpl);
        if (!pair?.access_token) return false;
        updateSessionTokens({
          accessToken: pair.access_token,
          refreshToken: pair.refresh_token,
        });
        try {
          options.onTokensRefreshed?.({
            accessToken: pair.access_token,
            refreshToken: pair.refresh_token,
          });
        } catch {
          /* ignore listener errors */
        }
        return true;
      } catch {
        return false;
      } finally {
        refreshInFlight = null;
      }
    })();
  }

  return refreshInFlight;
}

function buildHeaders(
  options: ApiClientOptions,
  init: RequestInit,
  accessToken?: string | null,
): Headers {
  const headers = new Headers(init.headers);
  if (!headers.has("Content-Type") && init.body) {
    headers.set("Content-Type", "application/json");
  }
  const token = accessToken ?? options.accessToken;
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  if (options.profileId) {
    headers.set("X-Profile-Id", options.profileId);
  }
  if (options.profileToken) {
    headers.set("X-Profile-Token", options.profileToken);
  }
  headers.set("X-Prairie-Device-Platform", "smarttv");
  headers.set("X-Prairie-Device-Name", "Prairie Smart TV");
  headers.set("X-Prairie-Image-Formats", imageFormatsHeaderValue());
  return headers;
}

async function performFetch(
  options: ApiClientOptions,
  path: string,
  init: RequestInit,
  accessToken?: string | null,
): Promise<Response> {
  const fetchImpl = options.fetchImpl ?? fetch;
  const headers = buildHeaders(options, init, accessToken);

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

  try {
    return await fetchImpl(joinUrl(options.serverUrl, path), {
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
}

async function parseError(response: Response): Promise<{
  body: unknown;
  message: string;
  code?: string;
}> {
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
  return { body, message, code };
}

export async function apiRequest<T>(
  options: ApiClientOptions,
  path: string,
  init: RequestInit = {},
): Promise<T> {
  let response = await performFetch(options, path, init);

  if (!response.ok) {
    const peek = await parseError(response);
    const authFailure =
      shouldNotifyUnauthorized(response.status, peek.code) && !isAuthLoginPath(path);

    if (authFailure) {
      const refreshed = await tryRefreshSession(options);
      if (refreshed) {
        let nextAccess: string | null = null;
        try {
          nextAccess = localStorage.getItem(ACCESS_TOKEN_KEY);
        } catch {
          nextAccess = null;
        }
        response = await performFetch(options, path, init, nextAccess);
        if (response.ok) {
          if (response.status === 204) return undefined as T;
          return (await response.json()) as T;
        }
        const retryError = await parseError(response);
        if (options.onUnauthorized && shouldNotifyUnauthorized(response.status, retryError.code)) {
          try {
            options.onUnauthorized();
          } catch {
            /* logout handlers must not mask the ApiError */
          }
        }
        throw new ApiError(retryError.message, response.status, retryError.code, retryError.body);
      }

      if (options.onUnauthorized) {
        try {
          options.onUnauthorized();
        } catch {
          /* logout handlers must not mask the ApiError */
        }
      }
    }

    throw new ApiError(peek.message, response.status, peek.code, peek.body);
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
  profileId?: string | null,
): string {
  const base =
    streamPath.startsWith("http://") || streamPath.startsWith("https://")
      ? streamPath
      : joinUrl(serverUrl, streamPath);

  if (!isSameServerOrigin(serverUrl, base)) return base;

  const params = new URLSearchParams();
  if (token) params.set("token", token);
  if (profileId) params.set("profile_id", profileId);
  if ([...params.keys()].length === 0) return base;

  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}${params.toString()}`;
}
