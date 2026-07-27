/// <reference types="node" />
// Vitest stubs CSS imports, so the stylesheet is read from disk instead.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "styles.css"), "utf8");

interface Rule {
  selectors: string[];
  body: string;
}

function rules(): Rule[] {
  const out: Rule[] = [];
  for (const [, selectorText, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!selectorText || body == null) continue;
    const selectors = selectorText
      .split(",")
      .map((selector: string) => selector.replace(/\s+/g, " ").trim())
      .filter(Boolean);
    if (!selectors.length) continue;
    out.push({ selectors, body });
  }
  return out;
}

function animatesBoxShadow(body: string): boolean {
  const transition = /transition:\s*([^;]*);/s.exec(body);
  return transition?.[1]?.includes("box-shadow") ?? false;
}

/** Selectors covered by a `[data-perf]` rule that no longer animates box-shadow. */
function perfCoveredSelectors(): Set<string> {
  const covered = new Set<string>();
  for (const rule of rules()) {
    if (animatesBoxShadow(rule.body)) continue;
    const dropsShadow = /transition:/.test(rule.body) || /box-shadow:\s*none/.test(rule.body);
    if (!dropsShadow) continue;
    for (const selector of rule.selectors) {
      const match = /^html\[data-perf="(?:low|balanced)"\]\s+(.*)$/.exec(selector);
      if (!match?.[1]) continue;
      covered.add(match[1].replace(/:focus(-visible)?$/, "").trim());
    }
  }
  return covered;
}

describe("perf-tier CSS", () => {
  it("is consumed by the stylesheet at all", () => {
    // main.tsx sets html[data-perf]; before this block existed nothing read it.
    expect(css).toContain('html[data-perf="low"]');
    expect(css).toContain('html[data-perf="balanced"]');
  });

  it("drops the box-shadow transition for every selector that animates one", () => {
    const covered = perfCoveredSelectors();
    const animated = new Set<string>();
    for (const rule of rules()) {
      if (!animatesBoxShadow(rule.body)) continue;
      for (const selector of rule.selectors) {
        if (selector.startsWith("html[data-perf")) continue;
        animated.add(selector);
      }
    }

    expect(animated.size).toBeGreaterThan(5);
    const uncovered = [...animated].filter((selector) => !covered.has(selector));
    expect(uncovered).toEqual([]);
  });

  it("replaces the focus glow with a flat outline on low and balanced tiers", () => {
    const focusRule = rules().find(
      (rule) =>
        rule.selectors.some((s) => s === 'html[data-perf="low"] .poster-card:focus') &&
        /box-shadow:\s*none/.test(rule.body),
    );
    expect(focusRule).toBeDefined();
    expect(focusRule?.body).toContain("outline:");
    // The focus affordance has to survive for buttons too, not only cards.
    expect(focusRule?.selectors).toContain('html[data-perf="low"] .focus-btn:focus');
  });

  it("avoids :is() in perf rules so pre-Chromium-88 TVs still match", () => {
    for (const rule of rules()) {
      const perfSelectors = rule.selectors.filter((s) => s.includes("[data-perf"));
      for (const selector of perfSelectors) {
        expect(selector).not.toContain(":is(");
      }
    }
  });
});
