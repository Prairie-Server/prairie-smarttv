import { useEffect } from "react";
import { subscribeBackKeys } from "../platform/backKey";

/** Invoke `onBack` when the TV remote Back / Escape / tizenhwkey is pressed. */
export function useBackKey(onBack: () => void, enabled = true): void {
  useEffect(() => {
    if (!enabled) return;
    return subscribeBackKeys((event) => {
      event.preventDefault?.();
      onBack();
    });
  }, [onBack, enabled]);
}
