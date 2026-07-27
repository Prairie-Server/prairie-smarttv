import { useEffect } from "react";
import { isBackKey } from "./spatialFocus";

/** Invoke `onBack` when the TV remote Back / Escape key is pressed. */
export function useBackKey(onBack: () => void, enabled = true): void {
  useEffect(() => {
    if (!enabled) return;
    function onKeyDown(event: KeyboardEvent) {
      if (!isBackKey(event.key)) return;
      if (event.defaultPrevented) return;
      event.preventDefault();
      onBack();
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onBack, enabled]);
}
