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
  fetchImpl?: typeof fetch;
  /** Request timeout in milliseconds. Defaults to 30s. */
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;

function joinUrl(base: string, path: string): string {
  const normalizedBase = base.replace(/\/+$/, "");
  const normalizedPath = path.startsWith("/") ? path : `/${path}`;
  return `${normalizedBase}${normalizedPath}`;
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
  headers.set("X-Prairie-Device-Platform", "smarttv");
  headers.set("X-Prairie-Device-Name", "Prairie Smart TV");

  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

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
    if (err instanceof Error && err.name === "AbortError") {
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
    throw new ApiError(message, response.status, code, body);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

/**
 * Resolve a stream_url from Prairie against the server base and attach token.
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

  if (!token) return base;

  const params = new URLSearchParams();
  params.set("token", token);
  const separator = base.includes("?") ? "&" : "?";
  return `${base}${separator}${params.toString()}`;
}
