/**
 * Scale the UI from a 1920×1080 design reference so rem/`px` chrome
 * stays readable on 4K/8K TV WebViews that report panel CSS pixels.
 */

export const DESIGN_WIDTH = 1920;
export const DESIGN_ROOT_FONT_PX = 16;

/** Clamp so tiny windows don't collapse and 8K doesn't explode layout. */
export function viewportScaleFactor(width: number): number {
  if (!Number.isFinite(width) || width <= 0) return 1;
  return Math.min(4, Math.max(0.75, width / DESIGN_WIDTH));
}

export function rootFontSizePx(scale: number): number {
  return DESIGN_ROOT_FONT_PX * scale;
}

/** Design pixels → device CSS pixels at the current viewport scale. */
export function designPx(px: number, scale: number): number {
  return Math.max(1, Math.round(px * scale));
}

export function currentViewportWidth(): number {
  return window.innerWidth || DESIGN_WIDTH;
}

/** Apply `--ui-scale` + root font-size on <html>. */
export function applyViewportScale(width: number = currentViewportWidth()): number {
  const scale = viewportScaleFactor(width);
  const root = document.documentElement;
  root.style.setProperty("--ui-scale", String(scale));
  root.style.fontSize = `${rootFontSizePx(scale)}px`;
  return scale;
}

/** Keep scale in sync with orientation / window changes. */
export function watchViewportScale(): () => void {
  const update = () => {
    applyViewportScale(currentViewportWidth());
  };
  update();
  window.addEventListener("resize", update);
  return () => window.removeEventListener("resize", update);
}
