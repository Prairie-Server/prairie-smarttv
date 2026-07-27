import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ScreenErrorBoundary } from "./ScreenErrorBoundary";

let container: HTMLDivElement;
let root: Root | null = null;

function mount(node: React.ReactNode) {
  act(() => {
    root = createRoot(container, { onUncaughtError: () => {} });
    root.render(node);
  });
}

beforeEach(() => {
  container = document.createElement("div");
  document.body.append(container);
  vi.spyOn(console, "error").mockImplementation(() => {});
});

afterEach(() => {
  if (root) {
    act(() => root?.unmount());
    root = null;
  }
  container.remove();
  vi.restoreAllMocks();
});

function Boom({ explode }: { explode: boolean }) {
  if (explode) throw new Error("kaboom");
  return <p>recovered</p>;
}

describe("ScreenErrorBoundary", () => {
  it("renders children when nothing throws", () => {
    mount(
      <ScreenErrorBoundary screen="This screen">
        <p>content</p>
      </ScreenErrorBoundary>,
    );
    expect(container.textContent).toContain("content");
  });

  it("keeps the failure recoverable instead of unmounting the tree", () => {
    mount(
      <ScreenErrorBoundary screen="This title">
        <Boom explode />
      </ScreenErrorBoundary>,
    );

    expect(container.textContent).toContain("Something went wrong");
    expect(container.textContent).toContain("This title could not be displayed");
    expect(container.textContent).toContain("kaboom");
    // The stack is shown on screen: packaged TV builds have no dev console.
    expect(container.querySelector(".error-screen__stack")?.textContent).toContain("kaboom");
    // Retry must be reachable with the remote.
    const buttons = [...container.querySelectorAll("button")].map((b) => b.textContent);
    expect(buttons).toContain("Try again");
    expect(console.error).toHaveBeenCalled();
  });

  it("renders Back only when a handler is supplied and invokes it", () => {
    const onBack = vi.fn();
    mount(
      <ScreenErrorBoundary screen="This title" onBack={onBack}>
        <Boom explode />
      </ScreenErrorBoundary>,
    );
    const back = [...container.querySelectorAll("button")].find((b) => b.textContent === "Back");
    expect(back).toBeTruthy();
    act(() => back?.click());
    expect(onBack).toHaveBeenCalledTimes(1);
  });

  it("clears the error and calls onRetry when Try again is pressed", () => {
    const onRetry = vi.fn();
    mount(
      <ScreenErrorBoundary screen="This title" onRetry={onRetry}>
        <Boom explode={false} />
      </ScreenErrorBoundary>,
    );
    expect(container.textContent).toContain("recovered");

    act(() => {
      root?.render(
        <ScreenErrorBoundary screen="This title" onRetry={onRetry}>
          <Boom explode />
        </ScreenErrorBoundary>,
      );
    });
    expect(container.textContent).toContain("Something went wrong");

    const retry = [...container.querySelectorAll("button")].find(
      (b) => b.textContent === "Try again",
    );
    act(() => {
      root?.render(
        <ScreenErrorBoundary screen="This title" onRetry={onRetry}>
          <Boom explode={false} />
        </ScreenErrorBoundary>,
      );
      retry?.click();
    });
    expect(onRetry).toHaveBeenCalledTimes(1);
    expect(container.textContent).toContain("recovered");
  });

  it("wraps non-Error throws", () => {
    function ThrowString(): never {
      throw "plain string";
    }
    mount(
      <ScreenErrorBoundary screen="This screen">
        <ThrowString />
      </ScreenErrorBoundary>,
    );
    expect(container.textContent).toContain("plain string");
  });
});
