import { useCallback, useEffect, useRef } from "react";

/**
 * Returns a cached, identity-stable `() => onSelect(id)` per id.
 *
 * Rails pass a fresh arrow function to every card on every render, which defeats
 * React.memo and makes an unrelated parent state change (or a virtualization
 * window growing by one) re-render every mounted card. On TV SoCs that whole-rail
 * re-render is one of the largest main-thread costs during D-pad navigation.
 */
export function useStableItemSelect<T extends string>(
  onSelect: (id: T) => void,
): (id: T) => () => void {
  const onSelectRef = useRef(onSelect);
  const handlers = useRef(new Map<T, () => void>());

  useEffect(() => {
    onSelectRef.current = onSelect;
  }, [onSelect]);

  return useCallback((id: T) => {
    const existing = handlers.current.get(id);
    if (existing) return existing;
    const handler = () => onSelectRef.current(id);
    handlers.current.set(id, handler);
    return handler;
  }, []);
}
