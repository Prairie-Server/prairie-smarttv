import type { PlatformKind } from "./types";
import { isStarfishEnvironment } from "./webos/starfish";

function hasAvPlay(): boolean {
  return typeof window !== "undefined" && Boolean(window.webapis?.avplay);
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
  if (isStarfishEnvironment()) return "webos";
  return "browser";
}

export function isTvPlatform(platform: PlatformKind = detectPlatform()): boolean {
  return platform === "tizen" || platform === "webos";
}
