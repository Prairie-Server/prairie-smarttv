import { isBackKey } from "../focus/spatialFocusKeys";

/**
 * Coalesce rapid duplicate Back events. Tizen often delivers both `tizenhwkey`
 * and a keydown for the same remote press; without this, one Back can pop two
 * routes (player → detail → home).
 */
let lastBackAt = 0;
const BACK_COALESCE_MS = 400;

export function shouldHandleBackNow(now = Date.now()): boolean {
  if (now - lastBackAt < BACK_COALESCE_MS) return false;
  lastBackAt = now;
  return true;
}

/** @internal Test helper. */
export function resetBackKeyCoalesceForTests(): void {
  lastBackAt = 0;
}

export type BackKeySubscription = {
  /** Keyboard-style Back / Escape / XF86Back / … */
  onKeyDown: (event: KeyboardEvent) => void;
  /** Samsung `tizenhwkey` with `keyName === "back"`. */
  onHwKey: (event: Event) => void;
};

/**
 * Subscribe to every Back signal the TV may emit. Callers should preventDefault
 * and run their exit/navigation when the returned handlers fire.
 *
 * `hwkey-event="enable"` in config.xml means an unhandled `tizenhwkey` back can
 * background/exit the packaged app — which looks like a blank Prairie shell if
 * `player-active` transparency is still applied.
 */
export function subscribeBackKeys(onBack: (event: Event) => void): () => void {
  const onKeyDown = (event: KeyboardEvent) => {
    if (!isBackKey(event.key) && event.key !== "BrowserBack") return;
    if (event.defaultPrevented) return;
    if (!shouldHandleBackNow()) {
      event.preventDefault();
      return;
    }
    onBack(event);
  };

  const onHwKey = (event: Event) => {
    const keyName = (event as { keyName?: string }).keyName;
    if (keyName !== "back") return;
    if (!shouldHandleBackNow()) {
      event.preventDefault?.();
      return;
    }
    onBack(event);
  };

  window.addEventListener("keydown", onKeyDown);
  document.addEventListener("tizenhwkey", onHwKey as EventListener);
  return () => {
    window.removeEventListener("keydown", onKeyDown);
    document.removeEventListener("tizenhwkey", onHwKey as EventListener);
  };
}
