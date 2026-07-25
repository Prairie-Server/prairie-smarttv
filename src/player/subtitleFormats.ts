/** Subtitle formats Smart TV backends can actually render client-side. */
const SUPPORTED_EXTENSIONS = /\.(vtt|srt|smi|sami|ttml|dfxp)(?:$|\?)/i;

export function isClientRenderableSubtitleUrl(url: string | undefined | null): boolean {
  if (!url) return false;
  return SUPPORTED_EXTENSIONS.test(url);
}

export function filterClientRenderableSubtitles<T extends { url: string; codec?: string }>(
  tracks: T[],
): T[] {
  return tracks.filter((track) => {
    const codec = (track.codec ?? "").toLowerCase();
    if (codec.includes("pgs") || codec.includes("hdmv") || codec === "sup") return false;
    if (codec.includes("ass") || codec.includes("ssa")) return false;
    return isClientRenderableSubtitleUrl(track.url);
  });
}
