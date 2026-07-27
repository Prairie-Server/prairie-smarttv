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

  it("does not run spatial navigation while typing left/right inside a text input", () => {
    const input = document.createElement("input");
    input.type = "text";
    input.value = "hello";
    input.setSelectionRange(2, 2);
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

  it("leaves a text input on ArrowUp so Back / QR stay reachable", () => {
    const back = document.createElement("button");
    const input = document.createElement("input");
    input.type = "text";
    document.body.append(back, input);
    place(back, 0, 0, 120, 48);
    place(input, 0, 80, 200, 48);
    input.focus();

    const event = new KeyboardEvent("keydown", { key: "ArrowUp", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: input });

    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(back);
    expect(event.defaultPrevented).toBe(true);
  });

  it("leaves a text input on ArrowLeft at the start of the field", () => {
    const back = document.createElement("button");
    const input = document.createElement("input");
    input.type = "text";
    input.value = "hi";
    input.setSelectionRange(0, 0);
    document.body.append(back, input);
    place(back, 0, 0, 120, 48);
    place(input, 140, 0, 200, 48);
    input.focus();

    const event = new KeyboardEvent("keydown", { key: "ArrowLeft", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: input });

    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(back);
  });

  it("defers caret motion for contentEditable, selections, and mid-field arrows", async () => {
    const { shouldDeferToEditableCaret } = await import("./spatialFocus");

    const editable = document.createElement("div");
    editable.contentEditable = "true";
    document.body.append(editable);
    expect(shouldDeferToEditableCaret(editable, "ArrowLeft")).toBe(true);
    expect(shouldDeferToEditableCaret(editable, "ArrowUp")).toBe(false);

    const select = document.createElement("select");
    document.body.append(select);
    expect(shouldDeferToEditableCaret(select, "ArrowRight")).toBe(true);

    const input = document.createElement("input");
    input.type = "text";
    input.value = "hello";
    input.setSelectionRange(1, 3);
    expect(shouldDeferToEditableCaret(input, "ArrowLeft")).toBe(true);

    input.setSelectionRange(5, 5);
    expect(shouldDeferToEditableCaret(input, "ArrowRight")).toBe(false);
    expect(shouldDeferToEditableCaret(input, "ArrowLeft")).toBe(true);

    const number = document.createElement("input");
    number.type = "number";
    number.value = "12";
    // happy-dom may report null selection on number inputs.
    expect(shouldDeferToEditableCaret(number, "ArrowRight")).toBe(true);

    expect(shouldDeferToEditableCaret(null, "ArrowLeft")).toBe(false);
  });

  it("keeps spatial navigation on checkbox inputs (TV toggles)", () => {
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    const button = document.createElement("button");
    document.body.append(checkbox, button);
    place(checkbox, 0, 0, 40, 40);
    place(button, 0, 100, 120, 48);
    checkbox.focus();

    const event = new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: checkbox });

    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(button);
    expect(event.defaultPrevented).toBe(true);
  });

  it("detects TV back keys", async () => {
    const { isBackKey, isEditableTarget } = await import("./spatialFocus");
    expect(isBackKey("Escape")).toBe(true);
    expect(isBackKey("XF86Back")).toBe(true);
    expect(isBackKey("GoBack")).toBe(true);
    expect(isBackKey("ArrowLeft")).toBe(false);

    const text = document.createElement("input");
    text.type = "text";
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    expect(isEditableTarget(text)).toBe(true);
    expect(isEditableTarget(checkbox)).toBe(false);
  });

  it("skips checkboxes nested in settings rows and aria-hidden controls", () => {
    const row = document.createElement("button");
    row.className = "settings-row";
    const nested = document.createElement("input");
    nested.type = "checkbox";
    row.append(nested);

    const hidden = document.createElement("button");
    hidden.setAttribute("aria-hidden", "true");

    const visible = document.createElement("button");
    document.body.append(row, hidden, visible);
    place(row, 0, 0);
    place(nested, 8, 8, 20, 20);
    place(hidden, 0, 80);
    place(visible, 0, 160);

    expect(listFocusables()).toEqual([row, visible]);
  });

  it("treats password and search inputs as editable, not radios", async () => {
    const { isEditableTarget } = await import("./spatialFocus");
    for (const type of ["password", "search", "email", "url", "tel", "number"] as const) {
      const input = document.createElement("input");
      input.type = type;
      expect(isEditableTarget(input)).toBe(true);
    }
    const radio = document.createElement("input");
    radio.type = "radio";
    expect(isEditableTarget(radio)).toBe(false);
    expect(isEditableTarget(null)).toBe(false);
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
