import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const flushSyncSpy = vi.fn();

vi.mock("react-dom", async (importOriginal) => {
  const actual = await importOriginal<typeof import("react-dom")>();
  return {
    ...actual,
    flushSync: (fn: () => void) => {
      flushSyncSpy();
      return actual.flushSync(fn);
    },
  };
});

let container: HTMLDivElement;
let root: Root | null = null;

const items = Array.from({ length: 200 }, (_, index) => ({ id: `i${index}` }));

async function mountRow() {
  const { MediaRow } = await import("./MediaRow");
  act(() => {
    root = createRoot(container);
    root.render(
      <MediaRow
        title="Row"
        items={items}
        getItemKey={(item) => item.id}
        renderItem={(item) => (
          <button type="button" data-name={item.id}>
            {item.id}
          </button>
        )}
      />,
    );
  });
  const scroller = container.querySelector<HTMLElement>(".media-row__scroller");
  if (!scroller) throw new Error("scroller missing");
  return scroller;
}

function focusedIndex(): string | undefined {
  return (document.activeElement as HTMLElement | null)?.closest<HTMLElement>("[data-focus-index]")
    ?.dataset.focusIndex;
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  flushSyncSpy.mockClear();
});

afterEach(() => {
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
  vi.restoreAllMocks();
});

describe("MediaRow virtualization", () => {
  it("mounts a window but advertises the full item count for index nav", async () => {
    const scroller = await mountRow();
    expect(scroller.dataset.focusCount).toBe("200");
    const mounted = scroller.querySelectorAll("[data-focus-index]").length;
    expect(mounted).toBeGreaterThan(0);
    expect(mounted).toBeLessThan(items.length);
  });

  it("steps across the row without a synchronous render inside keydown", async () => {
    const scroller = await mountRow();
    const { handleSpatialArrowKey } = await import("../focus/spatialFocus");

    scroller.querySelector<HTMLElement>('[data-focus-index="0"]')?.focus();
    flushSyncSpy.mockClear();

    // Walk well past the initial window edge, one step at a time.
    for (let step = 0; step < 40; step++) {
      act(() => {
        handleSpatialArrowKey(
          new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true }),
        );
      });
    }

    expect(focusedIndex()).toBe("40");
    // Each in-window step pre-expands the window for the next one, so no step
    // pays for a blocking flushSync render + layout inside the key handler.
    expect(flushSyncSpy).not.toHaveBeenCalled();
  });

  it("keeps the focused card mounted when several steps land in one frame", async () => {
    const scroller = await mountRow();
    const { handleSpatialArrowKey } = await import("../focus/spatialFocus");

    scroller.querySelector<HTMLElement>('[data-focus-index="0"]')?.focus();
    flushSyncSpy.mockClear();

    // Key repeat: many presses batched into a single React commit.
    act(() => {
      for (let step = 0; step < 15; step++) {
        handleSpatialArrowKey(
          new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true }),
        );
      }
    });

    expect(focusedIndex()).toBe("15");
    expect(document.activeElement).not.toBe(document.body);
  });
});
