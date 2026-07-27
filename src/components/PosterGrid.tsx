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
  type ReactElement,
  type ReactNode,
} from "react";
import { flushSync } from "react-dom";
import { registerFocusReveal } from "../focus/spatialFocus";

const DEFAULT_MIN_COLUMN_WIDTH = 150;
const DEFAULT_GAP = 16;
const DEFAULT_ROW_HEIGHT = 320;
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

function columnCountForWidth(width: number, minColumnWidth: number, gap: number): number {
  if (width <= 0) return 1;
  return Math.max(1, Math.floor((width + gap) / (minColumnWidth + gap)));
}

export function PosterGrid({
  children,
  className = "",
  itemCount,
  minColumnWidth = DEFAULT_MIN_COLUMN_WIDTH,
  gap = DEFAULT_GAP,
  estimatedRowHeight = DEFAULT_ROW_HEIGHT,
  overscanRows = DEFAULT_OVERSCAN_ROWS,
}: PosterGridProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(1280);
  const [scrollY, setScrollY] = useState(0);
  const [viewportH, setViewportH] = useState(
    typeof window !== "undefined" ? window.innerHeight : 720,
  );
  const [gridOffsetTop, setGridOffsetTop] = useState(0);
  const [forcedRows, setForcedRows] = useState<{ start: number; end: number } | null>(null);

  const childArray = useMemo(() => Children.toArray(children), [children]);
  const count = itemCount ?? childArray.length;
  const columns = columnCountForWidth(width, minColumnWidth, gap);
  const rowCount = Math.max(1, Math.ceil(count / Math.max(columns, 1)));

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
      setScrollY(window.scrollY || document.documentElement.scrollTop || 0);
      const el = rootRef.current;
      if (el) {
        setGridOffsetTop(el.getBoundingClientRect().top + (window.scrollY || 0));
      }
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  const naturalStartRow = Math.max(
    0,
    Math.floor((scrollY - gridOffsetTop) / estimatedRowHeight) - overscanRows,
  );
  const visibleRows = Math.ceil(viewportH / estimatedRowHeight) + 1;
  const naturalEndRow = Math.min(rowCount, naturalStartRow + visibleRows + overscanRows * 2);

  const startRow = forcedRows ? Math.min(forcedRows.start, naturalStartRow) : naturalStartRow;
  const endRow = forcedRows ? Math.max(forcedRows.end, naturalEndRow) : naturalEndRow;
  const startIndex = Math.min(count, Math.max(0, startRow) * columns);
  const endIndex = Math.min(count, Math.max(0, endRow) * columns);

  const reveal = useCallback(
    (index: number) => {
      const el = rootRef.current;
      if (!el) return null;
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
    [columns, overscanRows, rowCount],
  );

  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    return registerFocusReveal(el, reveal);
  }, [reveal]);

  useEffect(() => {
    if (!forcedRows) return;
    const handle = window.setTimeout(() => setForcedRows(null), 400);
    return () => window.clearTimeout(handle);
  }, [forcedRows]);

  const shouldVirtualize = count > columns * 3;
  const sliceStart = shouldVirtualize ? startIndex : 0;
  const sliceEnd = shouldVirtualize ? endIndex : count;
  const padTop = shouldVirtualize ? Math.max(0, startRow) * estimatedRowHeight : 0;
  const padBottom = shouldVirtualize
    ? Math.max(0, rowCount - Math.max(endRow, 0)) * estimatedRowHeight
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
