/**
 * Panel resolution helpers for Samsung Tizen.
 *
 * Tizen webviews almost always report 1920×1080 via `screen` / `innerWidth`
 * even on 4K/8K panels. Playback capabilities must use ProductInfo (or an
 * optional getRealResolution) so the server can remux native 4K instead of
 * forcing a 1080p re-encode.
 */

export type ProductInfoApi = {
  is8KPanelSupported?(): boolean;
  isUdPanelSupported?(): boolean;
  /** Some firmwares expose physical panel pixels as "3840x2160" / "7680x4320". */
  getRealResolution?(): string;
};

export function getProductInfo(): ProductInfoApi | null {
  return window.webapis?.productinfo ?? null;
}

/** Map a WxH (or "2160p") string to a Prairie max_resolution token. */
export function resolutionTokenFromPixels(raw: string | null | undefined): string {
  const value = (raw ?? "").trim().toLowerCase();
  if (!value) return "";
  const match = value.match(/(\d{3,5})\s*[x×]\s*(\d{3,5})/);
  if (match) {
    const width = Number(match[1]);
    const height = Number(match[2]);
    return resolutionTokenFromSize(width, height);
  }
  if (value.includes("4320") || value === "8k") return "2160p";
  if (value.includes("2160") || value === "4k" || value === "uhd") return "2160p";
  if (value.includes("1440")) return "1440p";
  if (value.includes("1080")) return "1080p";
  if (value.includes("720")) return "720p";
  return "";
}

export function resolutionTokenFromSize(width: number, height: number): string {
  const w = Math.max(width || 0, 0);
  const h = Math.max(height || 0, 0);
  // 8K panels still advertise 2160p for streaming — Prairie's encode ladder and
  // remux path treat 2160p as the 4K ceiling, which unblocks native 4K remux.
  if (h >= 2160 || w >= 3840) return "2160p";
  if (h >= 1440 || w >= 2560) return "1440p";
  if (h >= 1080 || w >= 1920) return "1080p";
  if (h > 0 || w > 0) return "720p";
  return "";
}

/**
 * Best-known panel max resolution for capability advertisement.
 * ProductInfo first on Tizen; screen/window only as a non-Tizen / fallback path.
 */
export function probePanelMaxResolution(
  input: {
    productInfo?: ProductInfoApi | null;
    screenWidth?: number;
    screenHeight?: number;
    windowWidth?: number;
    windowHeight?: number;
  } = {},
): string {
  const productInfo = input.productInfo === undefined ? getProductInfo() : input.productInfo;
  if (productInfo) {
    try {
      const real = productInfo.getRealResolution?.();
      const fromReal = resolutionTokenFromPixels(real);
      if (fromReal) return fromReal;
    } catch {
      /* older firmwares */
    }
    try {
      if (productInfo.is8KPanelSupported?.()) return "2160p";
    } catch {
      /* ignore */
    }
    try {
      if (productInfo.isUdPanelSupported?.()) return "2160p";
    } catch {
      /* ignore */
    }
  }

  const width = Math.max(
    input.screenWidth ?? (typeof screen !== "undefined" ? screen.width || 0 : 0),
    input.windowWidth ?? (typeof window !== "undefined" ? window.innerWidth || 0 : 0),
  );
  const height = Math.max(
    input.screenHeight ?? (typeof screen !== "undefined" ? screen.height || 0 : 0),
    input.windowHeight ?? (typeof window !== "undefined" ? window.innerHeight || 0 : 0),
  );
  return resolutionTokenFromSize(width, height) || "720p";
}

/** AVPlay ADAPTIVE_INFO FIXED_MAX_RESOLUTION value for a Prairie token. */
export function avPlayFixedMaxResolution(token: string | null | undefined): string {
  switch ((token ?? "").trim().toLowerCase()) {
    case "2160p":
    case "4k":
    case "uhd":
      return "3840x2160";
    case "1440p":
      return "2560x1440";
    case "720p":
      return "1280x720";
    case "1080p":
    default:
      return "1920x1080";
  }
}
