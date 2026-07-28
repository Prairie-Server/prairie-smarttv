import { useRef } from "react";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { useFocusRescue } from "./useFocusRescue";

// jsdom reports offsetParent as null for everything; listFocusables() treats
// that as "not visible". Make connected elements report a parent so focus
// candidates are discoverable, matching the spatialFocus test setup.
let offsetParentDescriptor: PropertyDescriptor | undefined;
beforeAll(() => {
  offsetParentDescriptor = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "offsetParent");
  Object.defineProperty(HTMLElement.prototype, "offsetParent", {
    configurable: true,
    get() {
      return (this as HTMLElement).isConnected ? document.body : null;
    },
  });
});
afterAll(() => {
  if (offsetParentDescriptor) {
    Object.defineProperty(HTMLElement.prototype, "offsetParent", offsetParentDescriptor);
  }
});

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  host = document.createElement("div");
  document.body.append(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
});

function Grid({ ids }: { ids: string[] }) {
  const ref = useRef<HTMLDivElement>(null);
  useFocusRescue(ref);
  return (
    <div ref={ref} data-focus-container="grid">
      {ids.map((id) => (
        <button key={id} type="button" data-id={id}>
          {id}
        </button>
      ))}
    </div>
  );
}

describe("useFocusRescue", () => {
  it("moves focus to a neighbour when the focused element is removed", () => {
    act(() => root.render(<Grid ids={["a", "b", "c"]} />));
    const b = host.querySelector<HTMLButtonElement>('[data-id="b"]')!;
    act(() => b.focus());
    expect(document.activeElement).toBe(b);

    // Remove the focused card (as a season swap / guide refresh would).
    act(() => root.render(<Grid ids={["a", "c"]} />));

    expect(document.activeElement).not.toBe(document.body);
    expect((document.activeElement as HTMLElement | null)?.tagName).toBe("BUTTON");
  });

  it("does nothing when no focusable remains after the removal", () => {
    act(() => root.render(<Grid ids={["a"]} />));
    const a = host.querySelector<HTMLButtonElement>('[data-id="a"]')!;
    act(() => a.focus());
    // Remove every item — there is nothing to rescue focus to.
    act(() => root.render(<Grid ids={[]} />));
    expect(document.activeElement).toBe(document.body);
  });

  it("does not steal focus that is elsewhere", () => {
    act(() => root.render(<Grid ids={["a", "b"]} />));
    const outside = document.createElement("button");
    document.body.append(outside);
    outside.focus();

    // A re-render must not yank focus away from an element outside the container.
    act(() => root.render(<Grid ids={["a", "b"]} />));
    expect(document.activeElement).toBe(outside);
    outside.remove();
  });
});
