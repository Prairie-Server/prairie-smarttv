import { type RefObject, useCallback, useEffect, useLayoutEffect, useRef } from "react";
import { listFocusables } from "./spatialFocus";

/**
 * Restores D-pad focus when the focused element is removed by a list mutation.
 *
 * A TV has no pointer, so if the focused element unmounts — On Now's 60s guide
 * refresh drops a program that just ended, or a season switch replaces the
 * episode grid — focus falls to `<body>` and the remote appears dead until the
 * user blindly guesses a direction. This watches the container the user is in
 * and, when the element it last held focus on detaches and focus has genuinely
 * fallen to the body, moves focus to the nearest remaining item (same index,
 * clamped) so navigation keeps working.
 *
 * It never steals focus that is somewhere else — it only acts when the previous
 * focus target is gone and nothing else has claimed focus.
 */
export function useFocusRescue<T extends HTMLElement>(containerRef: RefObject<T | null>): void {
  const lastFocused = useRef<HTMLElement | null>(null);
  const lastIndex = useRef(0);
  const attached = useRef<T | null>(null);

  const onFocusIn = useCallback((event: FocusEvent) => {
    const container = attached.current;
    if (!container) return;
    const target = event.target;
    if (target instanceof HTMLElement && container.contains(target)) {
      lastFocused.current = target;
      const index = listFocusables(container).indexOf(target);
      if (index >= 0) lastIndex.current = index;
    }
  }, []);

  // Deliberately dependency-free so it re-checks after every render: the
  // container often mounts later than the hook (On Now renders a skeleton until
  // the guide lands, the episode grid only exists for series). A one-shot mount
  // effect attaches to nothing on those paths and focus rescue never runs.
  useEffect(() => {
    const container = containerRef.current;
    if (container === attached.current) return;
    attached.current?.removeEventListener("focusin", onFocusIn);
    attached.current = container;
    container?.addEventListener("focusin", onFocusIn);
  });

  useEffect(
    () => () => {
      attached.current?.removeEventListener("focusin", onFocusIn);
      attached.current = null;
    },
    [onFocusIn],
  );

  useLayoutEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const prev = lastFocused.current;
    // Only rescue when the element we last held focus on has detached and focus
    // has fallen to the body — otherwise leave the current focus untouched.
    if (!prev || prev.isConnected) return;
    const active = document.activeElement;
    if (active && active !== document.body) return;
    const focusables = listFocusables(container);
    const next = focusables[Math.min(lastIndex.current, focusables.length - 1)];
    if (next) {
      next.focus();
      lastFocused.current = next;
    } else {
      lastFocused.current = null;
    }
  });
}
