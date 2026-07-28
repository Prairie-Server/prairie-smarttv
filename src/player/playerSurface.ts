import { useEffect } from "react";
import { scheduleCompositorRepaint } from "../ui/forceRepaint";

/**
 * The `player-active` class clears every opaque ancestor background so the
 * hardware video plane (AVPlay / Starfish) shows through the WebView.
 */
const PLAYER_ACTIVE_CLASS = "player-active";

/**
 * Restore the app's own backgrounds and force the TV to recomposite.
 *
 * Safe to call more than once — both player screens call it on their exit path
 * and again on unmount, because a Back press that also backgrounds the packaged
 * app would otherwise leave the transparent surface in place.
 */
export function clearPlayerSurface(): void {
  document.documentElement.classList.remove(PLAYER_ACTIVE_CLASS);
  document.body.classList.remove(PLAYER_ACTIVE_CLASS);
  scheduleCompositorRepaint();
}

/** Hold the transparent video surface for as long as a player screen is mounted. */
export function usePlayerSurface(): void {
  useEffect(() => {
    document.documentElement.classList.add(PLAYER_ACTIVE_CLASS);
    document.body.classList.add(PLAYER_ACTIVE_CLASS);
    return clearPlayerSurface;
  }, []);
}
