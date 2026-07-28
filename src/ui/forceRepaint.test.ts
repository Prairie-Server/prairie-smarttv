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
    // One frame pass + one per REPAINT_SCHEDULE_MS entry.
    expect(spy.mock.calls.length).toBe(5);
  });

  it("does not stack passes when scheduled repeatedly", () => {
    vi.useFakeTimers();
    const root = mountRoot();
    const spy = vi.spyOn(root, "offsetHeight", "get");
    scheduleCompositorRepaint();
    scheduleCompositorRepaint();
    scheduleCompositorRepaint();
    vi.advanceTimersByTime(1600);
    // Only the last schedule survives — the superseded frame callbacks are
    // invalidated rather than repainting a screen they no longer belong to.
    expect(spy.mock.calls.length).toBe(5);
  });

  it("cancels pending passes, including a frame already queued", () => {
    vi.useFakeTimers();
    const root = mountRoot();
    const spy = vi.spyOn(root, "offsetHeight", "get");
    scheduleCompositorRepaint();
    scheduleCompositorRepaint();
    cancelScheduledCompositorRepaint();
    vi.advanceTimersByTime(1600);
    expect(spy).not.toHaveBeenCalled();
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
