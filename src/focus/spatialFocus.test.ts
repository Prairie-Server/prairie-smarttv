import { afterEach, describe, expect, it } from "vitest";
import {
  findSpatialNeighbor,
  handleSpatialArrowKey,
  isArrowKey,
  listFocusables,
  registerFocusReveal,
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
    expect(isBackKey("BrowserBack")).toBe(true);
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

  it("navigates by index inside a horizontal focus container", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const a = document.createElement("button");
    const b = document.createElement("button");
    const c = document.createElement("button");
    a.dataset.focusIndex = "0";
    b.dataset.focusIndex = "1";
    c.dataset.focusIndex = "2";
    row.append(a, b, c);
    document.body.append(row);
    place(a, 0, 200);
    place(b, 120, 200);
    place(c, 240, 200);

    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
    expect(findSpatialNeighbor(b, "ArrowRight")).toBe(c);
    expect(findSpatialNeighbor(c, "ArrowRight")).toBeNull();
    expect(findSpatialNeighbor(c, "ArrowLeft")).toBe(b);
  });

  it("moves between stacked focus containers on ArrowUp/ArrowDown", () => {
    const top = document.createElement("div");
    top.dataset.focusContainer = "horizontal";
    const bottom = document.createElement("div");
    bottom.dataset.focusContainer = "horizontal";
    const t0 = document.createElement("button");
    const t1 = document.createElement("button");
    const b0 = document.createElement("button");
    const b1 = document.createElement("button");
    t0.dataset.focusIndex = "0";
    t1.dataset.focusIndex = "1";
    b0.dataset.focusIndex = "0";
    b1.dataset.focusIndex = "1";
    top.append(t0, t1);
    bottom.append(b0, b1);
    document.body.append(top, bottom);
    place(t0, 0, 0);
    place(t1, 120, 0);
    place(b0, 0, 200);
    place(b1, 120, 200);

    // Down from column 1 lands on column 1. Up restores the last index in the
    // destination container (Spotlight-style), not the source column.
    expect(findSpatialNeighbor(t1, "ArrowDown")).toBe(b1);
    expect(findSpatialNeighbor(b0, "ArrowUp")).toBe(t1);
  });

  it("clamps onto the nearest column of a shorter row instead of skipping it", () => {
    // Live TV guide shape: rows carry Watch plus zero to two Record buttons.
    const rows = [3, 1, 2].map((count, row) => {
      const container = document.createElement("div");
      container.dataset.focusContainer = "horizontal";
      container.dataset.focusCount = String(count);
      for (let column = 0; column < count; column++) {
        const button = document.createElement("button");
        button.dataset.focusIndex = String(column);
        button.textContent = `r${row}c${column}`;
        container.append(button);
        place(button, column * 120, row * 200);
      }
      document.body.append(container);
      return container;
    });

    const from = rows[0]!.children[2] as HTMLElement;
    // Row 1 has no column 2: land on its only button rather than jumping to row 2.
    const down = findSpatialNeighbor(from, "ArrowDown");
    expect(down?.textContent).toBe("r1c0");
    // Continuing down enters the next row at the column we just clamped to.
    expect(findSpatialNeighbor(down, "ArrowDown")?.textContent).toBe("r2c0");
  });

  it("navigates a grid container by columns", () => {
    const grid = document.createElement("div");
    grid.dataset.focusContainer = "grid";
    grid.dataset.focusColumns = "2";
    const buttons = [0, 1, 2, 3].map((index) => {
      const button = document.createElement("button");
      button.dataset.focusIndex = String(index);
      grid.append(button);
      return button;
    });
    document.body.append(grid);
    place(buttons[0]!, 0, 0);
    place(buttons[1]!, 120, 0);
    place(buttons[2]!, 0, 160);
    place(buttons[3]!, 120, 160);

    expect(findSpatialNeighbor(buttons[0]!, "ArrowRight")).toBe(buttons[1]);
    expect(findSpatialNeighbor(buttons[1]!, "ArrowLeft")).toBe(buttons[0]);
    expect(findSpatialNeighbor(buttons[0]!, "ArrowDown")).toBe(buttons[2]);
    expect(findSpatialNeighbor(buttons[2]!, "ArrowUp")).toBe(buttons[0]);
    expect(findSpatialNeighbor(buttons[2]!, "ArrowRight")).toBe(buttons[3]);
    expect(findSpatialNeighbor(buttons[3]!, "ArrowRight")).toBeNull();
  });

  it("estimates grid columns and exits the top/bottom of a grid", () => {
    const above = document.createElement("div");
    above.dataset.focusContainer = "horizontal";
    const a0 = document.createElement("button");
    a0.dataset.focusIndex = "0";
    above.append(a0);

    const grid = document.createElement("div");
    grid.dataset.focusContainer = "grid";
    const buttons = [0, 1, 2, 3].map((index) => {
      const button = document.createElement("button");
      button.dataset.focusIndex = String(index);
      grid.append(button);
      return button;
    });
    document.body.append(above, grid);
    place(a0, 0, 0);
    place(buttons[0]!, 0, 120);
    place(buttons[1]!, 120, 120);
    place(buttons[2]!, 0, 280);
    place(buttons[3]!, 120, 280);

    expect(findSpatialNeighbor(buttons[0]!, "ArrowUp")).toBe(a0);
    expect(findSpatialNeighbor(buttons[2]!, "ArrowDown")).toBeNull();
  });

  it("reveals virtualized indices through registerFocusReveal", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "3";
    const a = document.createElement("button");
    a.dataset.focusIndex = "0";
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);

    const b = document.createElement("button");
    b.dataset.focusIndex = "1";
    place(b, 120, 0);
    const unregister = registerFocusReveal(row, (index) => {
      if (index !== 1) return null;
      row.append(b);
      return b;
    });

    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
    unregister();
  });

  it("reveals virtualized indices when focusCount is absent", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const a = document.createElement("button");
    a.dataset.focusIndex = "0";
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);

    const b = document.createElement("button");
    b.dataset.focusIndex = "1";
    place(b, 120, 0);
    const unregister = registerFocusReveal(row, (index) => {
      if (index !== 1) return null;
      row.append(b);
      return b;
    });

    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
    unregister();
  });

  it("navigates a grid without stamped indices via DOM order", () => {
    const grid = document.createElement("div");
    grid.dataset.focusContainer = "grid";
    grid.dataset.focusColumns = "2";
    const buttons = [0, 1, 2, 3].map(() => {
      const button = document.createElement("button");
      grid.append(button);
      return button;
    });
    document.body.append(grid);
    place(buttons[0]!, 0, 0);
    place(buttons[1]!, 120, 0);
    place(buttons[2]!, 0, 160);
    place(buttons[3]!, 120, 160);

    expect(findSpatialNeighbor(buttons[0]!, "ArrowRight")).toBe(buttons[1]);
    expect(findSpatialNeighbor(buttons[0]!, "ArrowDown")).toBe(buttons[2]);
    expect(findSpatialNeighbor(buttons[2]!, "ArrowDown")).toBeNull();
  });

  it("navigates a vertical focus container with up/down", () => {
    const col = document.createElement("div");
    col.dataset.focusContainer = "vertical";
    const a = document.createElement("button");
    const b = document.createElement("button");
    a.dataset.focusIndex = "0";
    b.dataset.focusIndex = "1";
    col.append(a, b);
    document.body.append(col);
    place(a, 0, 0);
    place(b, 0, 80);

    expect(findSpatialNeighbor(a, "ArrowDown")).toBe(b);
    expect(findSpatialNeighbor(b, "ArrowUp")).toBe(a);
    expect(findSpatialNeighbor(b, "ArrowDown")).toBeNull();
    expect(findSpatialNeighbor(a, "ArrowLeft")).toBeNull();
    expect(findSpatialNeighbor(a, "ArrowRight")).toBeNull();
  });

  it("clamps to the nearest column when entering a ragged row from above", () => {
    const row1 = document.createElement("div");
    row1.dataset.focusContainer = "horizontal";
    row1.dataset.focusCount = "3";
    const watch1 = document.createElement("button");
    watch1.dataset.focusIndex = "0";
    const recNow = document.createElement("button");
    recNow.dataset.focusIndex = "1";
    const recNext = document.createElement("button");
    recNext.dataset.focusIndex = "2";
    row1.append(watch1, recNow, recNext);

    const row2 = document.createElement("div");
    row2.dataset.focusContainer = "horizontal";
    row2.dataset.focusCount = "1";
    const watch2 = document.createElement("button");
    watch2.dataset.focusIndex = "0";
    row2.append(watch2);

    document.body.append(row1, row2);
    place(watch1, 0, 0);
    place(recNow, 120, 0);
    place(recNext, 240, 0);
    place(watch2, 0, 200);

    recNext.focus();
    expect(findSpatialNeighbor(recNext, "ArrowDown")).toBe(watch2);
  });

  it("clamps to the nearest column when re-entering a shorter row", () => {
    const row1 = document.createElement("div");
    row1.dataset.focusContainer = "horizontal";
    row1.dataset.focusCount = "3";
    const watch1 = document.createElement("button");
    watch1.dataset.focusIndex = "0";
    const recNow = document.createElement("button");
    recNow.dataset.focusIndex = "1";
    const recNext = document.createElement("button");
    recNext.dataset.focusIndex = "2";
    row1.append(watch1, recNow, recNext);

    const row2 = document.createElement("div");
    row2.dataset.focusContainer = "horizontal";
    row2.dataset.focusCount = "1";
    const watch2 = document.createElement("button");
    watch2.dataset.focusIndex = "0";
    row2.append(watch2);

    document.body.append(row1, row2);
    place(watch1, 0, 0);
    place(recNow, 120, 0);
    place(recNext, 240, 0);
    place(watch2, 240, 200);

    recNext.focus();
    expect(findSpatialNeighbor(recNext, "ArrowDown")).toBe(watch2);

    // Row two only has column zero; re-enter row one on the nearest mounted column.
    row1.removeChild(recNext);
    expect(findSpatialNeighbor(watch2, "ArrowUp")).toBe(recNow);
  });

  it("clamps invalid focusCount and stays put at a horizontal edge", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "1";
    const a = document.createElement("button");
    const b = document.createElement("button");
    a.dataset.focusIndex = "0";
    b.dataset.focusIndex = "1";
    row.append(a, b);
    document.body.append(row);
    place(a, 0, 0);
    place(b, 120, 0);

    // focusCount=1 is below rendered count, so total falls back to rendered length.
    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
    expect(findSpatialNeighbor(b, "ArrowRight")).toBeNull();
  });

  it("scrolls into view when the focused neighbor is off-screen", () => {
    const a = document.createElement("button");
    const b = document.createElement("button");
    document.body.append(a, b);
    place(a, 0, 0);
    place(b, 0, window.innerHeight + 200);
    a.focus();
    let scrolled = false;
    b.scrollIntoView = () => {
      scrolled = true;
    };
    const event = new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(b);
    expect(scrolled).toBe(true);
  });

  it("ignores modified and already-handled arrow events", () => {
    const a = document.createElement("button");
    const b = document.createElement("button");
    document.body.append(a, b);
    place(a, 0, 0);
    place(b, 100, 0);
    a.focus();
    expect(
      handleSpatialArrowKey(new KeyboardEvent("keydown", { key: "ArrowRight", ctrlKey: true })),
    ).toBe(false);
    const prevented = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true });
    prevented.preventDefault();
    expect(handleSpatialArrowKey(prevented)).toBe(false);
  });

  it("uses focusCount when it is at least the rendered item count", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "4";
    const a = document.createElement("button");
    a.dataset.focusIndex = "0";
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);
    const revealed: number[] = [];
    registerFocusReveal(row, (index) => {
      revealed.push(index);
      const el = document.createElement("button");
      el.dataset.focusIndex = String(index);
      place(el, index * 120, 0);
      row.append(el);
      return el;
    });
    expect(findSpatialNeighbor(a, "ArrowRight")?.dataset.focusIndex).toBe("1");
    expect(revealed).toEqual([1]);
  });

  it("falls back when a reveal handler returns null but the node exists", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "2";
    const a = document.createElement("button");
    const b = document.createElement("button");
    a.dataset.focusIndex = "0";
    b.dataset.focusIndex = "1";
    // Only mount `a` initially; `b` is in the tree for querySelector after reveal misses.
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);
    place(b, 120, 0);
    registerFocusReveal(row, () => {
      row.append(b);
      return null;
    });
    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
  });

  it("skips zero-size and offscreen candidates outside containers", () => {
    const a = document.createElement("button");
    const ghost = document.createElement("button");
    const b = document.createElement("button");
    document.body.append(a, ghost, b);
    place(a, 0, 0);
    place(ghost, 0, 80, 0, 0);
    place(b, 0, 160);
    expect(listFocusables()).toEqual([a, b]);
  });

  it("parses bad focus indices as fallbacks and ignores empty containers", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const a = document.createElement("button");
    a.dataset.focusIndex = "nope";
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);
    expect(findSpatialNeighbor(a, "ArrowRight")).toBeNull();

    const empty = document.createElement("div");
    empty.dataset.focusContainer = "horizontal";
    document.body.append(empty);
    Object.defineProperty(empty, "offsetParent", { configurable: true, get: () => document.body });
    expect(findSpatialNeighbor(a, "ArrowDown")).toBeNull();
  });

  it("swallows edge stay-put on the index fast path without geometry", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "1";
    const a = document.createElement("button");
    a.dataset.focusIndex = "0";
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);
    a.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true });
    expect(handleSpatialArrowKey(event)).toBe(false);
    expect(event.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(a);
  });

  it("blurs an editable target when index navigation moves focus", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "2";
    const input = document.createElement("input");
    input.type = "text";
    input.value = "hi";
    input.setSelectionRange(2, 2);
    input.dataset.focusIndex = "0";
    const b = document.createElement("button");
    b.dataset.focusIndex = "1";
    row.append(input, b);
    document.body.append(row);
    place(input, 0, 0, 200, 40);
    place(b, 220, 0);
    input.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: input });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(b);
  });

  it("uses container-local geometry when index exit fails but a sibling is below", () => {
    // Horizontal container with stacked siblings: ArrowDown exits index-nav (null),
    // then local geometry still finds the sibling without a document sweep.
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const a = document.createElement("button");
    const b = document.createElement("button");
    row.append(a, b);
    document.body.append(row);
    place(a, 0, 0);
    place(b, 0, 120);
    a.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(b);
  });

  it("falls back to document geometry when the active container has a single item", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const a = document.createElement("button");
    const outside = document.createElement("button");
    row.append(a);
    document.body.append(row, outside);
    place(a, 0, 0);
    place(outside, 0, 160);
    a.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(outside);
  });

  it("skips nested-container index hits when resolving focus by data-focus-index", () => {
    const outer = document.createElement("div");
    outer.dataset.focusContainer = "horizontal";
    outer.dataset.focusCount = "2";
    const a = document.createElement("button");
    a.dataset.focusIndex = "0";
    const nested = document.createElement("div");
    nested.dataset.focusContainer = "horizontal";
    const nestedBtn = document.createElement("button");
    nestedBtn.dataset.focusIndex = "1";
    nested.append(nestedBtn);
    const b = document.createElement("button");
    b.dataset.focusIndex = "1";
    outer.append(a, nested, b);
    document.body.append(outer);
    place(a, 0, 0);
    place(nestedBtn, 40, 80);
    place(b, 120, 0);
    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
  });

  it("resolves reveal by list order when stamped indices are absent", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    row.dataset.focusCount = "2";
    const a = document.createElement("button");
    const b = document.createElement("button");
    a.dataset.focusIndex = "0";
    // `b` is discoverable only via list order (no data-focus-index).
    row.append(a);
    document.body.append(row);
    place(a, 0, 0);
    place(b, 120, 0);
    registerFocusReveal(row, () => {
      row.append(b);
      return null;
    });
    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
  });

  it("clamps an overshot index onto the last mounted item via the list path", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    // Undercounted focusCount forces rendered-length total after the counted reveal miss.
    row.dataset.focusCount = "1";
    const a = document.createElement("button");
    const b = document.createElement("button");
    // Intentionally omit data-focus-index so the direct query misses.
    row.append(a, b);
    document.body.append(row);
    place(a, 0, 0);
    place(b, 120, 0);
    expect(findSpatialNeighbor(a, "ArrowRight")).toBe(b);
  });

  it("blurs editable targets on the local geometry fallback path", () => {
    const row = document.createElement("div");
    row.dataset.focusContainer = "horizontal";
    const input = document.createElement("input");
    input.type = "text";
    const b = document.createElement("button");
    row.append(input, b);
    document.body.append(row);
    place(input, 0, 0, 200, 40);
    place(b, 0, 120);
    input.focus();
    const event = new KeyboardEvent("keydown", { key: "ArrowDown", cancelable: true });
    Object.defineProperty(event, "target", { configurable: true, value: input });
    expect(handleSpatialArrowKey(event)).toBe(true);
    expect(document.activeElement).toBe(b);
  });
});
