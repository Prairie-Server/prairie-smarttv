export interface AvPlayTrackInfo {
  type: string;
  index: number;
  extra_info?: string | Record<string, unknown>;
}

/** Prefer the newest TEXT track after an external subtitle path is attached. */
export function pickExternalTextTrackIndex(tracks: AvPlayTrackInfo[]): number | null {
  const text = tracks.filter((t) => String(t.type).toUpperCase() === "TEXT");
  if (!text.length) return null;
  return text[text.length - 1]!.index;
}
