/**
 * One-time raster decode capability detection for Prairie Smart TV clients.
 * Results are cached in localStorage and advertised via X-Prairie-Image-Formats.
 */

export type RasterFormat = "avif" | "webp" | "png";

const STORAGE_KEY = "prairie.imageFormats";
const DEFAULT_FORMATS: RasterFormat[] = ["webp", "png"];

let cached: RasterFormat[] | null = null;
let detectPromise: Promise<RasterFormat[]> | null = null;

function parseStored(value: string | null): RasterFormat[] | null {
  if (!value?.trim()) return null;
  const out: RasterFormat[] = [];
  const seen = new Set<RasterFormat>();
  for (const part of value.split(",")) {
    const token = part.trim().toLowerCase();
    if (token !== "avif" && token !== "webp" && token !== "png") continue;
    const format = token as RasterFormat;
    if (seen.has(format)) continue;
    seen.add(format);
    out.push(format);
  }
  return out.length > 0 ? out : null;
}

async function canDecodeMime(mime: string): Promise<boolean> {
  if (typeof createImageBitmap !== "function") {
    return false;
  }
  const bytes =
    mime === "image/avif"
      ? new Uint8Array([
          0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66, 0x00, 0x00, 0x00,
          0x00, 0x61, 0x76, 0x69, 0x66, 0x6d, 0x69, 0x66, 0x31, 0x6d, 0x69, 0x61, 0x66, 0x00, 0x00,
          0x00, 0x00,
        ])
      : new Uint8Array([
          0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38,
          0x20, 0x18, 0x00, 0x00, 0x00, 0x30, 0x01, 0x00, 0x9d, 0x01, 0x2a, 0x01, 0x00, 0x01, 0x00,
          0x02, 0x00, 0x34, 0x25, 0xa4, 0x00, 0x03, 0x70, 0x00, 0xfe, 0xfb, 0xfd, 0x50, 0x00,
        ]);
  try {
    const blob = new Blob([bytes], { type: mime });
    const bitmap = await createImageBitmap(blob);
    bitmap.close();
    return true;
  } catch {
    return false;
  }
}

async function probeFormats(): Promise<RasterFormat[]> {
  const out: RasterFormat[] = ["png"];
  if (await canDecodeMime("image/webp")) {
    out.unshift("webp");
  }
  if (await canDecodeMime("image/avif")) {
    out.unshift("avif");
  }
  return out;
}

import { preferredRasterFormatsForTier, resolvePerformanceTier } from "../perf/performanceTier";

let tieredCache: { source: readonly RasterFormat[]; result: RasterFormat[] } | null = null;

/**
 * Tier resolution reads localStorage and sniffs the UA. Card-heavy screens call
 * this once per image per render, and synchronous storage reads are expensive on
 * TV browsers — so the tiered result is memoized until the mode changes.
 */
function tieredFormats(source: readonly RasterFormat[]): RasterFormat[] {
  if (tieredCache && tieredCache.source === source) return tieredCache.result;
  const result = preferredRasterFormatsForTier(resolvePerformanceTier(), source);
  tieredCache = { source, result };
  return result;
}

/** Drop the memoized tier so a performance-mode change takes effect. */
export function resetImageFormatTierCache(): void {
  tieredCache = null;
}

export function getImageFormats(): RasterFormat[] {
  if (cached) return tieredFormats(cached);
  if (typeof localStorage !== "undefined") {
    const stored = parseStored(localStorage.getItem(STORAGE_KEY));
    if (stored) {
      cached = stored;
      return tieredFormats(stored);
    }
  }
  return tieredFormats(DEFAULT_FORMATS);
}

export async function detectImageFormats(): Promise<RasterFormat[]> {
  if (cached) return cached;
  if (detectPromise) return detectPromise;
  detectPromise = (async () => {
    const stored =
      typeof localStorage !== "undefined" ? parseStored(localStorage.getItem(STORAGE_KEY)) : null;
    if (stored) {
      cached = stored;
      return stored;
    }
    const detected = await probeFormats();
    cached = detected;
    if (typeof localStorage !== "undefined") {
      localStorage.setItem(STORAGE_KEY, detected.join(","));
    }
    return detected;
  })();
  return detectPromise;
}

export function imageFormatsHeaderValue(): string {
  return getImageFormats().join(",");
}

export function orderRasterCandidates(
  byFormat: Partial<Record<RasterFormat, string | null | undefined>>,
  preferred: readonly RasterFormat[] = getImageFormats(),
): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const format of preferred) {
    const url = byFormat[format]?.trim();
    if (!url || seen.has(url)) continue;
    seen.add(url);
    out.push(url);
  }
  return out;
}

/** @internal Test helper — clears in-memory and persisted format cache. */
export function resetImageFormatsCacheForTests(): void {
  cached = null;
  detectPromise = null;
  tieredCache = null;
  if (typeof localStorage !== "undefined") {
    localStorage.removeItem(STORAGE_KEY);
  }
}
