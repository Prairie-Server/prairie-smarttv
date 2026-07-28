import { useCallback, useEffect, useRef, useState } from "react";

/** Extra pixels above/below the viewport that still count as "near". */
const DEFAULT_MARGIN_PX = 240;

/**
 * Track whether a section has come close enough to the viewport to be worth
 * loading.
 *
 * A detail page mounts far more than it shows: episodes, cast, crew and
 * recommendations all sit below the fold on a 1080p panel. Admitting their
 * artwork on a single timer put ~20 image loads and one very large React commit
 * on the main thread at the same instant, which reads as the screen freezing and
 * the remote going dead for a beat.
 *
 * Prefer IntersectionObserver (viewport-relative, no scroll events required).
 * TV WebViews often move the page with `scrollIntoView` and never fire `window`
 * `"scroll"`, which stranded episode/cast art when we listened for scroll alone.
 * Keep a rect check on scroll/resize/focusin/rAF as a fallback for environments
 * where IO is missing or silent (happy-dom stubs, older WebViews).
 *
 * Once a section is near it stays near, and observers detach.
 */
export function useNearViewport(
  marginPx = DEFAULT_MARGIN_PX,
): [(node: HTMLElement | null) => void, boolean] {
  const [near, setNear] = useState(false);
  const [node, setNode] = useState<HTMLElement | null>(null);
  const nearRef = useRef(false);
  const frameRef = useRef<number | null>(null);

  const markNear = useCallback(() => {
    if (nearRef.current) return;
    nearRef.current = true;
    setNear(true);
  }, []);

  const checkRect = useCallback(() => {
    if (nearRef.current) return;
    if (!node) return;
    const rect = node.getBoundingClientRect();
    const viewportHeight = window.innerHeight || 720;
    // A zero-sized rect (not laid out yet, or a test DOM) counts as near: the
    // caller's other gates decide, and nothing is ever stranded unloaded.
    const measured = rect.height > 0 || rect.top !== 0 || rect.bottom !== 0;
    if (measured && (rect.top > viewportHeight + marginPx || rect.bottom < -marginPx)) {
      return;
    }
    markNear();
  }, [marginPx, markNear, node]);

  const scheduleCheck = useCallback(() => {
    if (nearRef.current) return;
    if (frameRef.current != null) return;
    frameRef.current = window.requestAnimationFrame(() => {
      frameRef.current = null;
      checkRect();
    });
  }, [checkRect]);

  useEffect(() => {
    if (near || !node) return;

    let observer: IntersectionObserver | null = null;
    if (typeof IntersectionObserver !== "undefined") {
      observer = new IntersectionObserver(
        (entries) => {
          if (entries.some((entry) => entry.isIntersecting)) markNear();
        },
        { root: null, rootMargin: `${marginPx}px 0px` },
      );
      observer.observe(node);
    }

    // capture: true so scroll on nested overflow roots still wakes us up.
    const onMaybeVisible = () => scheduleCheck();
    window.addEventListener("scroll", onMaybeVisible, { passive: true, capture: true });
    window.addEventListener("resize", onMaybeVisible);
    // D-pad navigation parks focus with scrollIntoView; many TV WebViews skip
    // emitting a scroll event for that, so focusin is the reliable signal.
    document.addEventListener("focusin", onMaybeVisible);

    // Ref can attach before layout; re-check on the next frame.
    scheduleCheck();

    return () => {
      observer?.disconnect();
      window.removeEventListener("scroll", onMaybeVisible, true);
      window.removeEventListener("resize", onMaybeVisible);
      document.removeEventListener("focusin", onMaybeVisible);
      if (frameRef.current != null) {
        window.cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };
  }, [near, node, marginPx, markNear, scheduleCheck]);

  const ref = useCallback((next: HTMLElement | null) => {
    setNode(next);
  }, []);

  return [ref, near];
}
