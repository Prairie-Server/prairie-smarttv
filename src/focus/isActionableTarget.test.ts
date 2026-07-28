import { describe, expect, it } from "vitest";
import { isActionableTarget } from "./isActionableTarget";

describe("isActionableTarget", () => {
  it("detects buttons and nested icon targets", () => {
    const button = document.createElement("button");
    const icon = document.createElement("span");
    button.append(icon);
    document.body.append(button);
    expect(isActionableTarget(button)).toBe(true);
    expect(isActionableTarget(icon)).toBe(true);
    button.remove();
  });

  it("rejects disconnected buttons so dead focus cannot swallow OK", () => {
    const button = document.createElement("button");
    document.body.append(button);
    button.remove();
    expect(isActionableTarget(button)).toBe(false);
  });

  it("rejects plain containers", () => {
    expect(isActionableTarget(document.createElement("div"))).toBe(false);
    expect(isActionableTarget(null)).toBe(false);
  });
});
