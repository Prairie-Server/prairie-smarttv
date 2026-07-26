import { apiRequest } from "./client";
import { parseHealth, type HealthIdentity } from "../discovery/discover";

/** Probe Prairie identity at GET /api/v1/health. */
export async function fetchServerHealth(
  serverUrl: string,
  fetchImpl?: typeof fetch,
): Promise<HealthIdentity | null> {
  try {
    const data = await apiRequest<unknown>(
      { serverUrl, fetchImpl, timeoutMs: 4_000 },
      "/api/v1/health",
      { method: "GET" },
    );
    return parseHealth(data);
  } catch {
    return null;
  }
}
