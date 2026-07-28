import { describe, expect, it } from "vitest";
import { isActionableTarget } from "./isActionableTarget";

describe("isActionableTarget", () => {
  it("detects buttons and nested icon targets", () => {
    const button = document.createElement("button");
    const icon = document.createElement("span");
    button.append(icon);
    expect(isActionableTarget(button)).toBe(true);
    expect(isActionableTarget(icon)).toBe(true);
  });

  it("rejects plain containers", () => {
    expect(isActionableTarget(document.createElement("div"))).toBe(false);
    expect(isActionableTarget(null)).toBe(false);
  });
});
