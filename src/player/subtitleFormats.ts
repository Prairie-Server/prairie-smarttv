/** Formats HTML5 / Starfish `<track>` elements can render without conversion. */
const CLIENT_RENDERABLE_EXTENSIONS = /\.vtt(?:$|\?)/i;

export function isClientRenderableSubtitleUrl(url: string | undefined | null): boolean {
  if (!url) return false;
  return CLIENT_RENDERABLE_EXTENSIONS.test(url);
}

export function filterClientRenderableSubtitles<T extends { url: string; codec?: string }>(
  tracks: T[],
): T[] {
  return tracks.filter((track) => {
    const codec = (track.codec ?? "").toLowerCase();
    if (codec.includes("pgs") || codec.includes("hdmv") || codec === "sup") return false;
    if (codec.includes("ass") || codec.includes("ssa")) return false;
    // Non-WebVTT text formats need conversion before <track src>; exclude for now.
    if (
      codec &&
      !codec.includes("webvtt") &&
      codec !== "vtt" &&
      (codec.includes("srt") ||
        codec.includes("smi") ||
        codec.includes("sami") ||
        codec.includes("ttml") ||
        codec.includes("dfxp"))
    ) {
      return false;
    }
    return isClientRenderableSubtitleUrl(track.url);
  });
}
