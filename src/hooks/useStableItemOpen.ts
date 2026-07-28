import { useCallback, useEffect, useRef } from "react";
import type { CatalogItem } from "../api/catalog";

/**
 * Returns a cached, identity-stable `() => onOpen(id, item)` per item.
 *
 * Hands the selected card to the navigation callback so the destination can
 * paint before its own request returns.
 *
 * The identity guarantee is the point and must not regress: rails pass a fresh
 * arrow to every card on every render otherwise, which defeats `React.memo` and
 * re-renders a whole rail whenever an unrelated parent state change lands. On TV
 * SoCs that is one of the largest main-thread costs during D-pad navigation. So
 * the handler for an id is created once and reused, while the *item* it will
 * pass is refreshed in a side map on each render — a card whose watch progress
 * updated hands over the new row without changing its handler's identity.
 */
export function useStableItemOpen(
  onOpen: (contentId: string, seed?: CatalogItem) => void,
): (item: CatalogItem) => () => void {
  const onOpenRef = useRef(onOpen);
  const handlers = useRef(new Map<string, () => void>());
  const seeds = useRef(new Map<string, CatalogItem>());

  useEffect(() => {
    onOpenRef.current = onOpen;
  }, [onOpen]);

  return useCallback((item: CatalogItem) => {
    seeds.current.set(item.content_id, item);
    const existing = handlers.current.get(item.content_id);
    if (existing) return existing;
    const handler = () => onOpenRef.current(item.content_id, seeds.current.get(item.content_id));
    handlers.current.set(item.content_id, handler);
    return handler;
  }, []);
}
