import type { PlatformKind } from "./types";

function hasAvPlay(): boolean {
  return typeof window !== "undefined" && Boolean(window.webapis?.avplay);
}

function hasWebOsSignals(): boolean {
  if (typeof window === "undefined") return false;
  if (window.webOS?.platform?.tv) return true;
  if (typeof window.PalmSystem !== "undefined") return true;
  const ua = navigator.userAgent;
  return /Web0S|webOS|LG Browser/i.test(ua);
}

function hasTizenSignals(): boolean {
  if (typeof window === "undefined") return false;
  if (hasAvPlay()) return true;
  const ua = navigator.userAgent;
  return /Tizen|SMART-TV|Samsung/i.test(ua) && /TV/i.test(ua);
}

/** Detect the runtime host for player selection. */
export function detectPlatform(): PlatformKind {
  if (hasAvPlay() || hasTizenSignals()) return "tizen";
  if (hasWebOsSignals()) return "webos";
  return "browser";
}

export function isTvPlatform(platform: PlatformKind = detectPlatform()): boolean {
  return platform === "tizen" || platform === "webos";
}
