import { afterEach, describe, expect, it } from "vitest";
import {
  findSpatialNeighbor,
  handleSpatialArrowKey,
  isArrowKey,
  listFocusables,
} from "./spatialFocus";

function place(el: HTMLElement, left: number, top: number, width = 40, height = 40) {
  el.getBoundingClientRect = () =>
    ({
      left,
      top,
      width,
      height,
      right: left + width,
      bottom: top + height,
      x: left,
      y: top,
      toJSON: () => ({}),
    }) as DOMRect;
  Object.defineProperty(el, "offsetParent", { configurable: true, get: () => document.body });
}

describe("spatialFocus", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("detects arrow keys", () => {
    expect(isArrowKey("ArrowLeft")).toBe(true);
    expect(isArrowKey("Enter")).toBe(false);
  });

  it("lists visible focusables and skips focus traps", () => {
    const a = document.createElement("button");
    const trap = document.createElement("div");
    trap.dataset.focusTrap = "off";
    const b = document.createElement("button");
    trap.append(b);
    document.body.append(a, trap);
    place(a, 0, 0);
    place(b, 0, 80);
    expect(listFocusables()).toEqual([a]);
  });

  it("picks the nearest neighbor in the arrow direction", () => {
    const left = document.createElement("button");
    const right = document.createElement("button");
    const below = document.createElement("button");
    document.body.append(left, right, below);
    place(left, 0, 0);
    place(right, 120, 0);
    place(below, 0, 120);

    expect(findSpatialNeighbor(left, "ArrowRight")).toBe(right);
    expect(findSpatialNeighbor(left, "ArrowDown")).toBe(below);
    expect(findSpatialNeighbor(left, "ArrowLeft")).toBeNull();
    expect(findSpatialNeighbor(null, "ArrowDown")).toBe(left);
  });

  it("handles keydown events", () => {
    const a = document.createElement("button");
    const b = document.createElement("button");
    document.body.append(a, b);
    place(a, 0, 0);
    place(b, 100, 0);
    a.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(b);
    expect(event.defaultPrevented).toBe(true);
    expect(handleSpatialArrowKey(new KeyboardEvent("keydown", { key: "Enter" }))).toBe(false);
  });
});
