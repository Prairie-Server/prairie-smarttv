import { normalizeServerUrl } from "../storage/persist";
import { fetchSetupStatus, type SetupStatusResponse } from "./auth";
import { ApiError } from "./client";
import { fetchServerHealth } from "./health";

const CHECK_TIMEOUT_MS = 6_000;

export type CheckServerSuccess = {
  ok: true;
  serverUrl: string;
  needsSetup: boolean;
  serverName?: string;
};

export type CheckServerFailure = {
  ok: false;
  message: string;
};

export type CheckServerResult = CheckServerSuccess | CheckServerFailure;

/**
 * Build URL candidates for a manual server address.
 *
 * - Explicit `http(s)://…` keeps that scheme only (matches Android TV / Apple).
 * - Bare host / host:port tries https first, then http.
 */
export function buildManualUrlCandidates(raw: string): string[] {
  const trimmed = raw.trim().replace(/\/+$/, "");
  if (!trimmed) return [];

  if (/^https?:\/\//i.test(trimmed)) {
    const normalized = normalizeServerUrl(trimmed);
    // Normalize scheme casing for stable registry IDs and comparisons.
    const lower = normalized.replace(/^https?:\/\//i, (m) => m.toLowerCase());
    return [lower];
  }

  const withoutSlashes = trimmed.replace(/^\/+/, "");
  return [
    normalizeServerUrl(`https://${withoutSlashes}`),
    normalizeServerUrl(`http://${withoutSlashes}`),
  ];
}

/** User-facing message for transport / TLS / DNS failures (not HTTP error bodies). */
export function networkFailureMessage(err: unknown): string {
  if (err instanceof ApiError) {
    if (err.code === "timeout" || err.status === 408) {
      return "Request timed out. Check the address and try again.";
    }
    return err.message.trim() || "Could not reach a Prairie server at that address.";
  }
  if (err instanceof TypeError) {
    // Browsers (incl. Tizen/webOS) surface TLS / refused / CORS as "Failed to fetch".
    return "Could not reach a Prairie server at that address. Check http vs https and the port.";
  }
  if (err instanceof Error && err.message.trim()) {
    const msg = err.message.trim();
    if (/failed to fetch|networkerror|load failed|network request failed/i.test(msg)) {
      return "Could not reach a Prairie server at that address. Check http vs https and the port.";
    }
    return msg;
  }
  return "Could not reach a Prairie server at that address.";
}

/**
 * Probe a candidate server before showing the login screen.
 * Requires GET /api/v1/auth/setup; health is best-effort for display name.
 */
export async function checkServer(
  serverUrl: string,
  options?: { fetchImpl?: typeof fetch; timeoutMs?: number },
): Promise<CheckServerResult> {
  const normalized = normalizeServerUrl(serverUrl);
  if (!normalized) {
    return { ok: false, message: "Enter a valid Prairie server address." };
  }

  let parsed: URL;
  try {
    parsed = new URL(normalized);
  } catch {
    return { ok: false, message: "Enter a valid Prairie server address." };
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return { ok: false, message: "Server URL must use http or https." };
  }
  if (parsed.username || parsed.password) {
    return { ok: false, message: "Server URL must not include credentials." };
  }

  const fetchImpl = options?.fetchImpl;
  const timeoutMs = options?.timeoutMs ?? CHECK_TIMEOUT_MS;

  let setup: SetupStatusResponse;
  try {
    setup = await fetchSetupStatus(normalized, fetchImpl, timeoutMs);
  } catch (err) {
    return { ok: false, message: networkFailureMessage(err) };
  }

  let serverName: string | undefined;
  try {
    const health = await fetchServerHealth(normalized, fetchImpl);
    const name = health?.serverName?.trim();
    if (name) serverName = name;
  } catch {
    /* health is optional */
  }

  return {
    ok: true,
    serverUrl: normalized,
    needsSetup: setup.needs_setup === true,
    serverName,
  };
}

/**
 * Try candidates in order until one responds to /auth/setup.
 * Used for manual entry (https → http when scheme omitted).
 */
export async function checkServerCandidates(
  candidates: string[],
  options?: { fetchImpl?: typeof fetch; timeoutMs?: number },
): Promise<CheckServerResult> {
  if (!candidates.length) {
    return { ok: false, message: "Enter a valid Prairie server address." };
  }

  let lastFailure: CheckServerFailure | null = null;
  for (const candidate of candidates) {
    const result = await checkServer(candidate, options);
    if (result.ok) return result;
    lastFailure = result;
  }
  return (
    lastFailure ?? {
      ok: false,
      message: "Could not reach a Prairie server at that address.",
    }
  );
}
