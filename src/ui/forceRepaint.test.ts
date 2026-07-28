import { afterEach, describe, expect, it, vi } from "vitest";
import { forceCompositorRepaint, scheduleCompositorRepaint } from "./forceRepaint";

afterEach(() => {
  document.getElementById("root")?.remove();
  vi.useRealTimers();
});

function mountRoot(): HTMLElement {
  const root = document.createElement("div");
  root.id = "root";
  document.body.append(root);
  return root;
}

describe("forceCompositorRepaint", () => {
  it("toggles display on the app root and restores it", () => {
    const root = mountRoot();
    root.style.display = "flex";
    forceCompositorRepaint();
    expect(root.style.display).toBe("flex");
  });

  it("falls back to body when there is no #root", () => {
    expect(() => forceCompositorRepaint()).not.toThrow();
    expect(document.body.style.display).toBe("");
  });
});

describe("scheduleCompositorRepaint", () => {
  it("repaints on the next frame and again shortly after", () => {
    vi.useFakeTimers();
    const root = mountRoot();
    const spy = vi.spyOn(root, "offsetHeight", "get");
    scheduleCompositorRepaint();
    vi.advanceTimersByTime(300);
    expect(spy.mock.calls.length).toBeGreaterThanOrEqual(1);
  });
});
