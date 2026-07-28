import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetBackKeyCoalesceForTests, shouldHandleBackNow, subscribeBackKeys } from "./backKey";

beforeEach(() => {
  resetBackKeyCoalesceForTests();
});

afterEach(() => {
  resetBackKeyCoalesceForTests();
});

describe("shouldHandleBackNow", () => {
  it("coalesces presses inside the window", () => {
    expect(shouldHandleBackNow(1000)).toBe(true);
    expect(shouldHandleBackNow(1100)).toBe(false);
    expect(shouldHandleBackNow(1500)).toBe(true);
  });
});

describe("subscribeBackKeys", () => {
  it("handles keyboard back and tizenhwkey back once per press", () => {
    const onBack = vi.fn((event: Event) => {
      event.preventDefault?.();
    });
    const unsubscribe = subscribeBackKeys(onBack);

    window.dispatchEvent(new KeyboardEvent("keydown", { key: "XF86Back", cancelable: true }));
    // Duplicate hwkey from the same remote press must not fire again.
    document.dispatchEvent(
      Object.assign(new Event("tizenhwkey", { cancelable: true }), { keyName: "back" }),
    );
    expect(onBack).toHaveBeenCalledTimes(1);

    resetBackKeyCoalesceForTests();
    document.dispatchEvent(
      Object.assign(new Event("tizenhwkey", { cancelable: true }), { keyName: "BACK" }),
    );
    expect(onBack).toHaveBeenCalledTimes(2);

    unsubscribe();
    resetBackKeyCoalesceForTests();
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", cancelable: true }));
    expect(onBack).toHaveBeenCalledTimes(2);
  });
});
