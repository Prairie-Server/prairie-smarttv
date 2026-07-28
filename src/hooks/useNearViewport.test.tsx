import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useNearViewport } from "./useNearViewport";

let container: HTMLDivElement;
let root: Root | null = null;

function farRect(): DOMRect {
  return {
    top: 4000,
    bottom: 4100,
    height: 100,
    width: 100,
    left: 0,
    right: 100,
    x: 0,
    y: 4000,
    toJSON() {
      return {};
    },
  };
}

function nearRect(): DOMRect {
  return {
    top: 200,
    bottom: 300,
    height: 100,
    width: 100,
    left: 0,
    right: 100,
    x: 0,
    y: 200,
    toJSON() {
      return {};
    },
  };
}

function Probe({
  marginPx,
  onNear,
  rect,
}: {
  marginPx?: number;
  onNear: (near: boolean) => void;
  rect: () => DOMRect;
}) {
  const [ref, near] = useNearViewport(marginPx);
  onNear(near);
  return (
    <div
      ref={(node) => {
        if (node) {
          vi.spyOn(node, "getBoundingClientRect").mockImplementation(rect);
        }
        ref(node);
      }}
      data-probe
    />
  );
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  Object.defineProperty(window, "innerHeight", { configurable: true, value: 720 });
});

afterEach(() => {
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
  vi.restoreAllMocks();
});

describe("useNearViewport", () => {
  it("stays far until IntersectionObserver reports intersecting", async () => {
    const observed: Element[] = [];
    let trigger: IntersectionObserverCallback | null = null;
    vi.stubGlobal(
      "IntersectionObserver",
      class {
        readonly root = null;
        readonly rootMargin = "";
        readonly thresholds = [];
        constructor(cb: IntersectionObserverCallback) {
          trigger = cb;
        }
        observe(el: Element) {
          observed.push(el);
        }
        disconnect() {}
        unobserve() {}
        takeRecords() {
          return [];
        }
      },
    );

    const rect = vi.fn(farRect);
    let near = false;
    await act(async () => {
      root = createRoot(container);
      root.render(
        <Probe
          rect={rect}
          onNear={(value) => {
            near = value;
          }}
        />,
      );
    });
    await act(async () => {
      await new Promise((r) => requestAnimationFrame(r));
    });

    expect(near).toBe(false);
    expect(observed.length).toBe(1);

    await act(async () => {
      trigger?.(
        [
          {
            isIntersecting: true,
            target: observed[0]!,
          } as IntersectionObserverEntry,
        ],
        {} as IntersectionObserver,
      );
    });
    expect(near).toBe(true);
  });

  it("admits on focusin when IO is missing (TV scrollIntoView often skips scroll)", async () => {
    vi.stubGlobal("IntersectionObserver", undefined);

    const rect = vi.fn(farRect);
    let near = false;
    await act(async () => {
      root = createRoot(container);
      root.render(
        <Probe
          rect={rect}
          onNear={(value) => {
            near = value;
          }}
        />,
      );
    });
    await act(async () => {
      await new Promise((r) => requestAnimationFrame(r));
    });
    expect(near).toBe(false);

    rect.mockImplementation(nearRect);
    await act(async () => {
      document.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
      await new Promise((r) => requestAnimationFrame(r));
    });
    expect(near).toBe(true);
  });
});
