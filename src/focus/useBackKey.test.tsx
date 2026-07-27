import { afterEach, describe, expect, it, vi } from "vitest";
import { act } from "react";
import { createRoot } from "react-dom/client";
import { useBackKey } from "./useBackKey";

describe("useBackKey", () => {
  afterEach(() => {
    document.body.replaceChildren();
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
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "XF86Back", cancelable: true }));
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowLeft", cancelable: true }));
    expect(onBack).toHaveBeenCalledTimes(2);

    await act(async () => {
      root.render(<Probe enabled={false} />);
    });
    onBack.mockClear();
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", cancelable: true }));
    expect(onBack).not.toHaveBeenCalled();

    await act(async () => {
      root.unmount();
    });
  });
});
