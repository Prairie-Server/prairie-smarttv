import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { resetBackKeyCoalesceForTests } from "../platform/backKey";
import { useBackKey } from "./useBackKey";

describe("useBackKey", () => {
  beforeEach(() => {
    resetBackKeyCoalesceForTests();
  });

  afterEach(() => {
    document.body.replaceChildren();
    resetBackKeyCoalesceForTests();
  });

  it("invokes onBack for TV back keys and ignores others", async () => {
    const onBack = vi.fn();
    const host = document.createElement("div");
    document.body.append(host);
    const root = createRoot(host);

    function Probe({ enabled = true }: { enabled?: boolean }) {
      useBackKey(onBack, enabled);
      return <span>ok</span>;
    }

    await act(async () => {
      root.render(<Probe />);
    });

    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", cancelable: true }));
    resetBackKeyCoalesceForTests();
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "XF86Back", cancelable: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", cancelable: true }));
    expect(onBack).toHaveBeenCalledTimes(2);

    resetBackKeyCoalesceForTests();
    document.dispatchEvent(
      Object.assign(new Event("tizenhwkey", { cancelable: true }), { keyName: "back" }),
    );
    expect(onBack).toHaveBeenCalledTimes(3);

    await act(async () => {
      root.render(<Probe enabled={false} />);
    });
    onBack.mockClear();
    resetBackKeyCoalesceForTests();
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", cancelable: true }));
    expect(onBack).not.toHaveBeenCalled();

    await act(async () => {
      root.unmount();
    });
  });
});
