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
    expect(handleSpatialArrowKey(new KeyboardEvent("keydown", { key: "ArrowUp" }))).toBe(false);
  });

  it("does not run spatial navigation while typing in an input", () => {
    const input = document.createElement("input");
    const button = document.createElement("button");
    document.body.append(input, button);
    place(input, 0, 0, 200, 48);
    place(button, 220, 0, 120, 48);
    input.focus();

    const event = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: input });

    expect(handleSpatialArrowKey(event)).toBe(false);
    expect(document.activeElement).toBe(input);
    expect(event.defaultPrevented).toBe(false);
  });

  it("returns early when fewer than two focusables or no neighbor", () => {
    const alone = document.createElement("button");
    document.body.append(alone);
    place(alone, 0, 0);
    alone.focus();
    expect(handleSpatialArrowKey(new KeyboardEvent("keydown", { key: "ArrowRight" }))).toBe(false);
    expect(findSpatialNeighbor(alone, "ArrowRight", [])).toBeNull();
    expect(findSpatialNeighbor(alone, "ArrowUp", [alone])).toBeNull();
    expect(isArrowKey("ArrowUp")).toBe(true);
    expect(isArrowKey("ArrowDown")).toBe(true);
  });

  it("keeps left/right on the button row instead of jumping to a full-width input above", () => {
    const password = document.createElement("input");
    const signIn = document.createElement("button");
    const back = document.createElement("button");
    document.body.append(password, signIn, back);
    place(password, 0, 0, 400, 48);
    place(signIn, 0, 80, 120, 48);
    place(back, 140, 80, 160, 48);

    expect(findSpatialNeighbor(signIn, "ArrowRight")).toBe(back);
    expect(findSpatialNeighbor(back, "ArrowLeft")).toBe(signIn);
    expect(findSpatialNeighbor(signIn, "ArrowUp")).toBe(password);
  });
});
