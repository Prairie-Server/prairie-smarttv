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
 * Proximity is measured with `getBoundingClientRect` on a rAF-throttled scroll
 * listener rather than IntersectionObserver: this runs on exactly one element
 * per section, and unlike IO it behaves identically on every WebView we ship to.
 * Once a section is near it stays near, and the listener detaches.
 */
export function useNearViewport(
  marginPx = DEFAULT_MARGIN_PX,
): [(node: HTMLElement | null) => void, boolean] {
  const [near, setNear] = useState(false);
  const nodeRef = useRef<HTMLElement | null>(null);
  const nearRef = useRef(false);
  const frameRef = useRef<number | null>(null);

  const check = useCallback(() => {
    if (nearRef.current) return;
    const node = nodeRef.current;
    if (!node) return;
    const rect = node.getBoundingClientRect();
    const viewportHeight = window.innerHeight || 720;
    // A zero-sized rect (not laid out yet, or a test DOM) counts as near: the
    // caller's other gates decide, and nothing is ever stranded unloaded.
    const measured = rect.height > 0 || rect.top !== 0 || rect.bottom !== 0;
    if (measured && (rect.top > viewportHeight + marginPx || rect.bottom < -marginPx)) return;
    nearRef.current = true;
    setNear(true);
  }, [marginPx]);

  useEffect(() => {
    if (near) return;
    const onScroll = () => {
      if (frameRef.current != null) return;
      frameRef.current = window.requestAnimationFrame(() => {
        frameRef.current = null;
        check();
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      if (frameRef.current != null) {
        window.cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };
  }, [check, near]);

  const ref = useCallback(
    (node: HTMLElement | null) => {
      nodeRef.current = node;
      if (node) check();
    },
    [check],
  );

  return [ref, near];
}
