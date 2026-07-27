/**
 * Scale the UI from a 1920×1080 design reference.
 *
 * Samsung/LG TV WebViews often keep a 1920×1080 CSS viewport even on 4K/8K
 * panels (the compositor upscales). In that case `innerWidth` alone stays ~1920
 * and a pure CSS-width scale never enlarges chrome — so we also detect the
 * physical panel class and apply a chrome multiplier.
 */

export const DESIGN_WIDTH = 1920;
export const DESIGN_ROOT_FONT_PX = 16;

export type PanelClass = "fhd" | "uhd" | "uhd8k";

/** Extra rem scale when the CSS viewport is locked at ~1080p on a larger panel. */
export const PANEL_CHROME_SCALE: Record<PanelClass, number> = {
  fhd: 1,
  uhd: 1.28,
  uhd8k: 1.55,
};

export interface ProductInfoApi {
  is8KPanelSupported?(): boolean;
  isUdPanelSupported?(): boolean;
}

function getProductInfo(): ProductInfoApi | null {
  const webapis = window.webapis as { productinfo?: ProductInfoApi } | undefined;
  return webapis?.productinfo ?? null;
}

/**
 * Prefer Samsung productinfo panel probes; fall back to screen vs CSS width.
 */
export function detectPanelClass(
  input: {
    cssWidth?: number;
    screenWidth?: number;
    productInfo?: ProductInfoApi | null;
  } = {},
): PanelClass {
  const productInfo = input.productInfo === undefined ? getProductInfo() : input.productInfo;
  if (productInfo) {
    try {
      if (productInfo.is8KPanelSupported?.()) return "uhd8k";
    } catch {
      /* ignore */
    }
    try {
      if (productInfo.isUdPanelSupported?.()) return "uhd";
    } catch {
      /* ignore */
    }
  }

  const cssWidth = input.cssWidth ?? (typeof window !== "undefined" ? window.innerWidth || 0 : 0);
  const screenWidth =
    input.screenWidth ?? (typeof window !== "undefined" ? window.screen?.width || 0 : 0);
  const hint = Math.max(cssWidth, screenWidth);
  if (hint >= 7680) return "uhd8k";
  if (hint >= 3840) return "uhd";
  return "fhd";
}

/** Clamp so tiny windows don't collapse and 8K doesn't explode layout. */
export function viewportScaleFactor(width: number, panelClass?: PanelClass): number {
  if (!Number.isFinite(width) || width <= 0) return 1;
  const cssScale = width / DESIGN_WIDTH;

  // WebView already reports 4K/8K CSS pixels — scale from width alone.
  if (width >= DESIGN_WIDTH * 1.5) {
    return Math.min(4, Math.max(0.75, cssScale));
  }

  // Narrow/devtools windows: shrink with CSS width (ignore panel chrome).
  if (width < DESIGN_WIDTH * 0.75) {
    return Math.min(4, Math.max(0.75, cssScale));
  }

  const panel = panelClass ?? detectPanelClass({ cssWidth: width });
  const chrome = PANEL_CHROME_SCALE[panel];
  return Math.min(4, Math.max(0.75, Math.max(cssScale, chrome)));
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
