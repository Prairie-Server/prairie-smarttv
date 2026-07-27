import { normalizeServerUrl } from "./persist";

export type ValidatedServerUrl =
  | { ok: true; url: string }
  | { ok: false; message: string };

function isDigits(value: string): boolean {
  if (value.length === 0) return false;
  for (let i = 0; i < value.length; i += 1) {
    const ch = value.charCodeAt(i);
    if (ch < 48 || ch > 57) return false;
  }
  return true;
}

function isIpv4Literal(host: string): boolean {
  const parts = host.split(".");
  if (parts.length !== 4) return false;
  for (const part of parts) {
    if (part.length === 0 || part.length > 3) return false;
    if (!isDigits(part)) return false;
    const value = Number.parseInt(part, 10);
    if (!Number.isFinite(value) || value < 0 || value > 255) return false;
  }
  return true;
}

function isPrivateIpv4(host: string): boolean {
  if (!isIpv4Literal(host)) return false;
  const parts = host.split(".").map((p) => Number.parseInt(p, 10));
  const a = parts[0]!;
  const b = parts[1]!;

  // RFC1918 + loopback + link-local.
  if (a === 10) return true;
  if (a === 192 && b === 168) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  return false;
}

export function isPrivateOrLocalHost(hostPart: string): boolean {
  let host = hostPart.trim().toLowerCase();
  // URL.hostname may include brackets for IPv6 in some environments.
  if (host.startsWith("[") && host.endsWith("]")) {
    host = host.slice(1, -1);
  }
  if (!host) return false;

  if (host === "localhost" || host === "::1") return true;

  // mDNS-style hosts.
  if (host.endsWith(".local")) return true;

  // IPv4 literal.
  if (isIpv4Literal(host)) return isPrivateIpv4(host);

  // IPv6 literals (URL.hostname strips brackets).
  if (host.includes(":")) {
    // Link-local: fe80::/10  → fe8*, fe9*, fea*, feb*
    return host.startsWith("fe8") || host.startsWith("fe9") || host.startsWith("fea") || host.startsWith("feb");
  }

  return false;
}

/**
 * Validate a user-entered Prairie server base URL.
 *
 * Security policy:
 * - Accept http(s) only.
 * - Reject credentials.
 * - HTTP is only allowed for private/LAN hosts (loopback, RFC1918, link-local).
 *   Public hosts require HTTPS.
 */
export function validateServerUrl(raw: string): ValidatedServerUrl {
  const trimmed = normalizeServerUrl(raw);
  if (!trimmed) {
    return { ok: false, message: "Enter your Prairie server URL" };
  }

  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return { ok: false, message: "Server URL must be a valid http(s) address" };
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return { ok: false, message: "Server URL must use http or https" };
  }

  if (parsed.username || parsed.password) {
    return { ok: false, message: "Server URL must not include credentials" };
  }

  const hostname = parsed.hostname;
  if (!hostname) {
    return { ok: false, message: "Server URL must be a valid http(s) address" };
  }

  if (parsed.protocol === "http:" && !isPrivateOrLocalHost(hostname)) {
    return { ok: false, message: "Use HTTPS, or HTTP only for a local/LAN server" };
  }

  return { ok: true, url: trimmed };
}

