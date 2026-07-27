/**
 * Source-type decision for the HTML5 backend.
 *
 * Tizen's WebView (Chromium 85 on Tizen 6.5) has no native HLS in <video>, so
 * assigning a .m3u8 to `video.src` silently never loads — the manifest is never
 * fetched and the server eventually reaps the orphaned ffmpeg. MSE is available,
 * so hls.js (light build) can demux MPEG-TS / fMP4 segments for playback.
 */

export type Html5SourceKind = "native-hls" | "hls-js" | "progressive";

const HLS_MIME_TYPES = [
  "application/vnd.apple.mpegurl",
  "application/x-mpegurl",
  "audio/mpegurl",
  "vnd.apple.mpegurl",
];

/** True when the URL or MIME type identifies an HLS manifest. */
export function isHlsSource(url: string, mimeType?: string): boolean {
  const mime = mimeType?.trim().toLowerCase() ?? "";
  if (mime && HLS_MIME_TYPES.includes(mime)) return true;
  const path = url.split("?")[0]?.split("#")[0]?.toLowerCase() ?? "";
  return path.endsWith(".m3u8");
}

export interface Html5SourceInput {
  url: string;
  mimeType?: string;
  /** `video.canPlayType` result for an HLS MIME type ("probably"/"maybe"/""). */
  nativeHlsSupport?: string;
  /** `Hls.isSupported()` — MSE plus the codecs hls.js needs. */
  hlsJsSupported?: boolean;
}

/**
 * Picks how the HTML5 backend should load a source. Native HLS wins when the
 * WebView claims it (future WebKit builds, Safari); otherwise hls.js handles
 * manifests, and everything else stays a direct `video.src` assignment.
 */
export function resolveHtml5Source(input: Html5SourceInput): Html5SourceKind {
  if (!isHlsSource(input.url, input.mimeType)) return "progressive";
  if (input.nativeHlsSupport) return "native-hls";
  if (input.hlsJsSupported) return "hls-js";
  // No native HLS and no MSE: assigning src is the only remaining option, and
  // the error surfaces through the media element instead of hanging silently.
  return "progressive";
}

/**
 * hls.js settings tuned for TV hardware.
 *
 * Workers are disabled because they are unstable on some Tizen builds, and the
 * buffer caps keep a long movie from exhausting WebView memory — the default
 * unbounded back buffer is enough to OOM a low-RAM panel mid-film.
 */
export const TV_HLS_CONFIG = {
  enableWorker: false,
  lowLatencyMode: false,
  maxBufferLength: 30,
  maxMaxBufferLength: 60,
  backBufferLength: 30,
  // Segment fetches on TV Wi-Fi can be slow; fail over rather than stall.
  manifestLoadingTimeOut: 20_000,
  fragLoadingTimeOut: 30_000,
} as const;
