import {
  Children,
  cloneElement,
  isValidElement,
  memo,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from "react";
import { flushSync } from "react-dom";
import { registerFocusReveal } from "../focus/spatialFocus";
import { currentViewportWidth, designPx, viewportScaleFactor } from "../ui/viewportScale";

/** Design-px metrics (1920×1080). Scaled by ui-scale so JS columns match CSS rem. */
const DEFAULT_MIN_COLUMN_WIDTH = 150;
const DEFAULT_GAP = 16;
const DEFAULT_ROW_HEIGHT = 320;
/** Keep only ~1–2 rows around the viewport; 6 was enough to mount whole pages. */
const DEFAULT_OVERSCAN_ROWS = 2;

interface PosterGridProps {
  children?: ReactNode;
  className?: string;
  /** Explicit item count for virtualization metadata (defaults to child count). */
  itemCount?: number;
  minColumnWidth?: number;
  gap?: number;
  estimatedRowHeight?: number;
  overscanRows?: number;
}

function stampFocusIndex(node: ReactNode, index: number): ReactNode {
  if (!isValidElement(node)) return node;
  const element = node as ReactElement<{ "data-focus-index"?: number }>;
  return cloneElement(element, { "data-focus-index": index });
}

export function columnCountForWidth(width: number, minColumnWidth: number, gap: number): number {
  if (width <= 0) return 1;
  return Math.max(1, Math.floor((width + gap) / (minColumnWidth + gap)));
}

function PosterGridInner({
  children,
  className = "",
  itemCount,
  minColumnWidth = DEFAULT_MIN_COLUMN_WIDTH,
  gap = DEFAULT_GAP,
  estimatedRowHeight = DEFAULT_ROW_HEIGHT,
  overscanRows = DEFAULT_OVERSCAN_ROWS,
}: PosterGridProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(() => viewportScaleFactor(currentViewportWidth()));
  const [width, setWidth] = useState(1280);
  const [scrollY, setScrollY] = useState(0);
  const [viewportH, setViewportH] = useState(
    typeof window !== "undefined" ? window.innerHeight : 720,
  );
  const [gridOffsetTop, setGridOffsetTop] = useState(0);
  const [forcedRows, setForcedRows] = useState<{ start: number; end: number } | null>(null);
  const scrollRafRef = useRef<number | null>(null);

  const childArray = useMemo(() => Children.toArray(children), [children]);
  const count = itemCount ?? childArray.length;

  // CSS columns use rem (scaled by root font-size / ui-scale). Match that here
  // so D-pad row jumps and virtualization windows stay aligned on 4K/8K panels.
  const scaledMinColumn = designPx(minColumnWidth, scale);
  const scaledGap = designPx(gap, scale);
  const scaledRowHeight = designPx(estimatedRowHeight, scale);
  const columns = columnCountForWidth(width, scaledMinColumn, scaledGap);
  const rowCount = Math.max(1, Math.ceil(count / Math.max(columns, 1)));

  useLayoutEffect(() => {
    const updateScale = () => setScale(viewportScaleFactor(currentViewportWidth()));
    updateScale();
    window.addEventListener("resize", updateScale);
    return () => window.removeEventListener("resize", updateScale);
  }, []);

  useLayoutEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const update = () => {
      setWidth(el.clientWidth || 1280);
      setViewportH(window.innerHeight || 720);
      setGridOffsetTop(el.getBoundingClientRect().top + (window.scrollY || 0));
    };
    update();
    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", update);
      return () => window.removeEventListener("resize", update);
    }
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [count, columns]);

  useEffect(() => {
    const onScroll = () => {
      if (scrollRafRef.current != null) return;
      scrollRafRef.current = window.requestAnimationFrame(() => {
        scrollRafRef.current = null;
        setScrollY(window.scrollY || document.documentElement.scrollTop || 0);
        const el = rootRef.current;
        if (el) {
          setGridOffsetTop(el.getBoundingClientRect().top + (window.scrollY || 0));
        }
      });
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (scrollRafRef.current != null) {
        window.cancelAnimationFrame(scrollRafRef.current);
      }
    };
  }, []);

  const naturalStartRow = Math.max(
    0,
    Math.floor((scrollY - gridOffsetTop) / scaledRowHeight) - overscanRows,
  );
  const visibleRows = Math.ceil(viewportH / scaledRowHeight) + 1;
  const naturalEndRow = Math.min(rowCount, naturalStartRow + visibleRows + overscanRows * 2);

  const startRow = forcedRows ? Math.min(forcedRows.start, naturalStartRow) : naturalStartRow;
  const endRow = forcedRows ? Math.max(forcedRows.end, naturalEndRow) : naturalEndRow;
  const startIndex = Math.min(count, Math.max(0, startRow) * columns);
  const endIndex = Math.min(count, Math.max(0, endRow) * columns);

  /** Grow the mounted rows around `index` on the next commit (no flushSync). */
  const prefetchAround = useCallback(
    (index: number) => {
      const row = Math.floor(index / Math.max(columns, 1));
      const start = Math.max(0, row - overscanRows);
      const end = Math.min(rowCount, row + overscanRows + 1);
      setForcedRows((prev) => {
        if (prev && prev.start <= start && prev.end >= end) return prev;
        return prev
          ? { start: Math.min(prev.start, start), end: Math.max(prev.end, end) }
          : { start, end };
      });
    },
    [columns, overscanRows, rowCount],
  );

  const reveal = useCallback(
    (index: number) => {
      const el = rootRef.current;
      if (!el) return null;

      const existing = el.querySelector<HTMLElement>(`[data-focus-index="${index}"]`);
      if (existing) {
        existing.scrollIntoView({ block: "nearest", inline: "nearest" });
        // Keep the next step inside the mounted rows.
        prefetchAround(index);
        return existing;
      }

      const row = Math.floor(index / Math.max(columns, 1));
      flushSync(() => {
        setForcedRows({
          start: Math.max(0, row - overscanRows),
          end: Math.min(rowCount, row + overscanRows + 1),
        });
      });
      const node = el.querySelector<HTMLElement>(`[data-focus-index="${index}"]`);
      node?.scrollIntoView({ block: "nearest", inline: "nearest" });
      return node;
    },
    [columns, overscanRows, rowCount, prefetchAround],
  );

  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    return registerFocusReveal(el, reveal);
  }, [reveal]);

  // Drop the forced rows once scrolling covers them, instead of on a timer that
  // could unmount the focused card mid-navigation.
  useEffect(() => {
    if (!forcedRows) return;
    if (naturalStartRow <= forcedRows.start && naturalEndRow >= forcedRows.end) {
      setForcedRows(null);
    }
  }, [forcedRows, naturalStartRow, naturalEndRow]);

  // Virtualize as soon as there is more than ~2 viewport rows of content.
  const shouldVirtualize = count > columns * 2;
  const sliceStart = shouldVirtualize ? startIndex : 0;
  const sliceEnd = shouldVirtualize ? endIndex : count;
  const padTop = shouldVirtualize ? Math.max(0, startRow) * scaledRowHeight : 0;
  const padBottom = shouldVirtualize
    ? Math.max(0, rowCount - Math.max(endRow, 0)) * scaledRowHeight
    : 0;

  return (
    <div
      ref={rootRef}
      className={`poster-grid${className ? ` ${className}` : ""}`}
      data-focus-container="grid"
      data-focus-columns={columns}
      data-focus-count={count}
      style={
        shouldVirtualize
          ? {
              paddingTop: padTop,
              paddingBottom: padBottom,
            }
          : undefined
      }
    >
      {childArray.slice(sliceStart, sliceEnd).map((child, offset) => {
        const index = sliceStart + offset;
        return (
          <div
            key={isValidElement(child) && child.key != null ? child.key : index}
            className="poster-grid__cell"
          >
            {stampFocusIndex(child, index)}
          </div>
        );
      })}
    </div>
  );
}

export const PosterGrid = memo(PosterGridInner);
