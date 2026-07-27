import {
  Children,
  cloneElement,
  isValidElement,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ReactElement,
  type ReactNode,
} from "react";
import { flushSync } from "react-dom";
import { registerFocusReveal } from "../focus/spatialFocus";

export type MediaRowVariant = "poster" | "landscape";

const VARIANT_METRICS: Record<
  MediaRowVariant,
  { itemWidth: number; gap: number; minHeight: string }
> = {
  poster: { itemWidth: 155, gap: 14, minHeight: "18.25rem" },
  landscape: { itemWidth: 352, gap: 14, minHeight: "14.5rem" },
};

interface MediaRowBaseProps {
  title: string;
  /** Shimmer title bar for skeleton rows (avoids empty→title height jump). */
  skeleton?: boolean;
  variant?: MediaRowVariant;
  className?: string;
}

interface MediaRowChildrenProps extends MediaRowBaseProps {
  children: ReactNode;
  itemCount?: never;
  renderItem?: never;
  getItemKey?: never;
}

interface MediaRowVirtualProps<T> extends MediaRowBaseProps {
  items: readonly T[];
  renderItem: (item: T, index: number) => ReactNode;
  getItemKey?: (item: T, index: number) => string | number;
  children?: never;
}

export type MediaRowProps<T = unknown> = MediaRowChildrenProps | MediaRowVirtualProps<T>;

function computeWindow(
  scrollLeft: number,
  viewport: number,
  itemStride: number,
  count: number,
  overscan: number,
): { start: number; end: number } {
  if (count <= 0 || itemStride <= 0) return { start: 0, end: 0 };
  const start = Math.max(0, Math.floor(scrollLeft / itemStride) - overscan);
  const visible = Math.ceil(viewport / itemStride) + 1;
  const end = Math.min(count, start + visible + overscan * 2);
  return { start, end };
}

function stampFocusIndex(node: ReactNode, index: number): ReactNode {
  if (!isValidElement(node)) return node;
  const element = node as ReactElement<{ "data-focus-index"?: number }>;
  return cloneElement(element, { "data-focus-index": index });
}

export function MediaRow<T>(props: MediaRowProps<T>) {
  const { title, skeleton = false, variant = "poster", className = "" } = props;
  const metrics = VARIANT_METRICS[variant];
  const scrollerRef = useRef<HTMLDivElement>(null);
  const [scrollLeft, setScrollLeft] = useState(0);
  const [viewport, setViewport] = useState(1280);

  const isVirtual = "items" in props && Array.isArray(props.items) && props.renderItem != null;
  const items = isVirtual ? props.items : null;
  const count = items?.length ?? 0;
  const itemStride = metrics.itemWidth + metrics.gap;
  const overscan = variant === "landscape" ? 3 : 5;

  const windowRange = useMemo(
    () => computeWindow(scrollLeft, viewport, itemStride, count, overscan),
    [scrollLeft, viewport, itemStride, count, overscan],
  );

  const [forcedRange, setForcedRange] = useState<{ start: number; end: number } | null>(null);
  const range = forcedRange
    ? {
        start: Math.min(forcedRange.start, windowRange.start),
        end: Math.max(forcedRange.end, windowRange.end),
      }
    : windowRange;

  useLayoutEffect(() => {
    const el = scrollerRef.current;
    if (!el) return;
    const update = () => setViewport(el.clientWidth || 1280);
    update();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", update);
      return () => window.removeEventListener("resize", update);
    }
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const reveal = useCallback(
    (index: number) => {
      const el = scrollerRef.current;
      if (!el || !items) return null;
      const nextStart = Math.max(0, index - overscan);
      const nextEnd = Math.min(count, index + overscan + 1);
      flushSync(() => {
        setForcedRange({ start: nextStart, end: nextEnd });
      });
      const targetLeft = Math.max(
        0,
        index * itemStride - Math.max(0, (el.clientWidth - metrics.itemWidth) / 2),
      );
      if (Math.abs(el.scrollLeft - targetLeft) > 2) {
        el.scrollLeft = targetLeft;
        setScrollLeft(el.scrollLeft);
      }
      return el.querySelector<HTMLElement>(`[data-focus-index="${index}"]`);
    },
    [items, count, overscan, itemStride, metrics.itemWidth],
  );

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el || !isVirtual) return;
    return registerFocusReveal(el, reveal);
  }, [isVirtual, reveal]);

  useEffect(() => {
    if (!forcedRange) return;
    const handle = window.setTimeout(() => setForcedRange(null), 400);
    return () => window.clearTimeout(handle);
  }, [forcedRange]);

  let body: ReactNode;
  let focusCount: number | undefined;

  if (isVirtual && items && props.renderItem) {
    focusCount = count;
    const padLeft = range.start * itemStride;
    const padRight = Math.max(0, (count - range.end) * itemStride);
    const slice: ReactNode[] = [];
    for (let i = range.start; i < range.end; i++) {
      const item = items[i]!;
      const key = props.getItemKey ? props.getItemKey(item, i) : i;
      slice.push(
        <div
          key={key}
          className="media-row__item"
          style={{ width: metrics.itemWidth } satisfies CSSProperties}
        >
          {stampFocusIndex(props.renderItem(item, i), i)}
        </div>,
      );
    }
    body = (
      <>
        {padLeft > 0 ? (
          <div className="media-row__spacer" style={{ width: padLeft }} aria-hidden />
        ) : null}
        {slice}
        {padRight > 0 ? (
          <div className="media-row__spacer" style={{ width: padRight }} aria-hidden />
        ) : null}
      </>
    );
  } else if ("children" in props) {
    const childArray = Children.toArray(props.children);
    focusCount = childArray.length;
    body = childArray.map((child, index) => (
      <div
        key={isValidElement(child) && child.key != null ? child.key : index}
        className="media-row__item"
      >
        {stampFocusIndex(child, index)}
      </div>
    ));
  } else {
    body = null;
  }

  return (
    <section
      className={`media-row media-row--${variant}${skeleton ? " media-row--skeleton" : ""}${
        className ? ` ${className}` : ""
      }`}
      style={{ minHeight: metrics.minHeight }}
    >
      {skeleton ? (
        <div className="media-row__title media-row__title--skeleton" aria-hidden="true" />
      ) : (
        <h2 className="media-row__title">{title}</h2>
      )}
      <div
        ref={scrollerRef}
        className="media-row__scroller"
        data-focus-container="horizontal"
        data-focus-count={focusCount}
        onScroll={(event) => setScrollLeft(event.currentTarget.scrollLeft)}
      >
        {body}
      </div>
    </section>
  );
}
