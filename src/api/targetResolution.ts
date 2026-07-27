/**
 * Pick the encode ladder resolution for POST /playback/transcode/start.
 *
 * Never upscale past the panel (`maxResolution`); never downscale a 4K source
 * to 1080p just because that used to be the conservative default — remux/copy
 * keeps native resolution, and full encodes target min(source, device max).
 */

const RESOLUTION_HEIGHT: Record<string, number> = {
  "2160p": 2160,
  "4k": 2160,
  uhd: 2160,
  "3840x2160": 2160,
  "1440p": 1440,
  "2560x1440": 1440,
  "1080p": 1080,
  "1920x1080": 1080,
  "720p": 720,
  "1280x720": 720,
  "480p": 480,
  "420p": 420,
  "360p": 360,
};

/** Canonical Prairie resolution token (`2160p`, `1080p`, …), or "" if unknown. */
export function normalizeResolution(raw: string | null | undefined): string {
  const value = (raw ?? "").trim().toLowerCase();
  if (!value) return "";
  if (RESOLUTION_HEIGHT[value] === 2160) return "2160p";
  if (RESOLUTION_HEIGHT[value] === 1440) return "1440p";
  if (RESOLUTION_HEIGHT[value] === 1080) return "1080p";
  if (RESOLUTION_HEIGHT[value] === 720) return "720p";
  if (RESOLUTION_HEIGHT[value] === 480) return "480p";
  if (RESOLUTION_HEIGHT[value] === 420) return "420p";
  if (RESOLUTION_HEIGHT[value] === 360) return "360p";
  const match = value.match(/(\d{3,4})\s*[pP]?$/);
  if (match?.[1]) {
    const height = Number(match[1]);
    if (height >= 2160) return "2160p";
    if (height >= 1440) return "1440p";
    if (height >= 1080) return "1080p";
    if (height >= 720) return "720p";
    if (height >= 480) return "480p";
    return "360p";
  }
  return "";
}

function resolutionHeight(token: string): number {
  return RESOLUTION_HEIGHT[token] ?? 0;
}

/**
 * `min(source, device max)` as a Prairie resolution token.
 * Falls back to the device max (defaulting to 1080p) when the source is unknown.
 */
export function resolveTargetResolution(
  sourceResolution: string | null | undefined,
  maxResolution: string | null | undefined,
): string {
  const max = normalizeResolution(maxResolution) || "1080p";
  const source = normalizeResolution(sourceResolution);
  if (!source) return max;
  return resolutionHeight(source) <= resolutionHeight(max) ? source : max;
}

/** Bitrate ladder matched to the chosen target resolution. */
export function targetBitrateKbpsForResolution(resolution: string): number {
  switch (normalizeResolution(resolution)) {
    case "2160p":
      return 20_000;
    case "1440p":
      return 12_000;
    case "1080p":
      return 6_000;
    case "720p":
      return 3_000;
    case "480p":
      return 1_500;
    default:
      return 6_000;
  }
}
