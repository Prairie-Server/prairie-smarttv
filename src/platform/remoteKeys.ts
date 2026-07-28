/**
 * TV remote key handling.
 *
 * Two problems this module solves:
 *
 * 1. Tizen only delivers the four arrows, Enter, Back and the number keys to a
 *    web app by default. Every other remote key (Play, Pause, Play/Pause,
 *    Rewind, Fast Forward, …) is consumed by the platform, which reacts by
 *    showing its own native media OSD on top of our player. The app must call
 *    `tizen.tvinputdevice.registerKey()` for each key it wants delivered
 *    instead — that is what stops the native helper from appearing.
 *
 * 2. The WebKit/Chromium builds shipped on TVs predate reliable `KeyboardEvent.key`
 *    for remote keys: media and Back keys arrive as `Unidentified` (or an empty
 *    string) with only a vendor `keyCode`. Screens therefore must not read
 *    `event.key` directly — use `remoteKeyName()`.
 */

/** Vendor key codes → the `KeyboardEvent.key` name we normalize to. */
const KEY_CODE_NAMES: Record<number, string> = {
  8: "Backspace",
  13: "Enter",
  27: "Escape",
  32: " ",
  37: "ArrowLeft",
  38: "ArrowUp",
  39: "ArrowRight",
  40: "ArrowDown",
  // Tizen (and most Samsung remotes)
  19: "MediaPause",
  412: "MediaRewind",
  413: "MediaStop",
  415: "MediaPlay",
  417: "MediaFastForward",
  10009: "XF86Back",
  10252: "MediaPlayPause",
  // webOS
  461: "XF86Back",
};

/** Keys the TV hands us without a usable `event.key`. */
function isUsableKeyName(key: string | undefined): key is string {
  return Boolean(key) && key !== "Unidentified" && key !== "Undefined";
}

/**
 * Canonical key name for a remote/keyboard event. Falls back to the vendor
 * `keyCode` table when the platform gives no usable `event.key`.
 */
export function remoteKeyName(event: Pick<KeyboardEvent, "key" | "keyCode">): string {
  if (isUsableKeyName(event.key)) return event.key;
  const mapped = KEY_CODE_NAMES[event.keyCode];
  return mapped ?? "";
}

/** True for the OK / centre-of-the-D-pad button. */
export function isSelectKey(key: string): boolean {
  return key === "Enter" || key === " " || key === "Spacebar";
}

/** Media transport keys we ask Tizen to deliver instead of handling natively. */
export const MEDIA_KEY_NAMES = [
  "MediaPlayPause",
  "MediaPlay",
  "MediaPause",
  "MediaStop",
  "MediaRewind",
  "MediaFastForward",
] as const;

interface TvInputDevice {
  registerKey?: (name: string) => void;
  getSupportedKeys?: () => Array<{ name?: string }>;
}

function getTvInputDevice(): TvInputDevice | null {
  const tizen = (window as { tizen?: { tvinputdevice?: TvInputDevice } }).tizen;
  return tizen?.tvinputdevice ?? null;
}

/**
 * Claim the media transport keys on Tizen. Without this the TV shows its own
 * play/pause overlay and the app never sees the press. No-op off Tizen, and
 * per-key failures are ignored so an unsupported key cannot break the rest.
 *
 * Returns the key names that were successfully registered.
 */
export function registerRemoteMediaKeys(): string[] {
  const device = getTvInputDevice();
  if (!device?.registerKey) return [];

  let supported: Set<string> | null = null;
  try {
    const keys = device.getSupportedKeys?.() ?? [];
    if (keys.length > 0) {
      supported = new Set(keys.map((entry) => String(entry?.name ?? "")));
    }
  } catch {
    // Older firmwares: register blind rather than skipping everything.
  }

  const registered: string[] = [];
  for (const name of MEDIA_KEY_NAMES) {
    if (supported && !supported.has(name)) continue;
    try {
      device.registerKey(name);
      registered.push(name);
    } catch {
      // Key unavailable on this model — the platform keeps handling it.
    }
  }
  return registered;
}
