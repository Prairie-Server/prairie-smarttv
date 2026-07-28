import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cancelScheduledCompositorRepaint,
  forceCompositorRepaint,
  scheduleCompositorRepaint,
} from "./forceRepaint";

afterEach(() => {
  cancelScheduledCompositorRepaint();
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
  it("repaints on the next frame and again across a decaying window", () => {
    vi.useFakeTimers();
    const root = mountRoot();
    const spy = vi.spyOn(root, "offsetHeight", "get");
    scheduleCompositorRepaint();
    // Covers the late-paint window so a slow destination screen is un-holed
    // after its content lands, not only on the first (still-blank) frame.
    vi.advanceTimersByTime(1600);
    expect(spy.mock.calls.length).toBeGreaterThanOrEqual(2);
  });

  it("cancels pending passes so repeated calls do not stack", () => {
    vi.useFakeTimers();
    const root = mountRoot();
    const spy = vi.spyOn(root, "offsetHeight", "get");
    scheduleCompositorRepaint();
    cancelScheduledCompositorRepaint();
    vi.advanceTimersByTime(1600);
    // The rAF pass may already have fired; the timed passes must not.
    expect(spy.mock.calls.length).toBeLessThanOrEqual(1);
  });

  it("falls back to a timeout when requestAnimationFrame is unavailable", () => {
    vi.useFakeTimers();
    const raf = window.requestAnimationFrame;
    (window as unknown as { requestAnimationFrame?: unknown }).requestAnimationFrame = undefined;
    try {
      const root = mountRoot();
      const spy = vi.spyOn(root, "offsetHeight", "get");
      scheduleCompositorRepaint();
      vi.advanceTimersByTime(1600);
      expect(spy.mock.calls.length).toBeGreaterThanOrEqual(1);
    } finally {
      window.requestAnimationFrame = raf;
    }
  });
});
