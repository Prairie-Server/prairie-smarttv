import type { FileVersion, WatchDetail } from "../api/watch";
import { selectFileVersion } from "../api/watch";

/** Normalize Prairie / ffmpeg audio codec labels for set membership checks. */
export function normalizeAudioCodec(raw: string | null | undefined): string {
  return (raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

/**
 * Whether `codec` is Direct-Play / remux-copy safe given the codecs we
 * advertised to Prairie in `codecs_audio`.
 */
export function isAudioCodecSupported(
  codec: string | null | undefined,
  supportedCodecs: readonly string[],
): boolean {
  const normalized = normalizeAudioCodec(codec);
  if (!normalized) return true;

  const supported = new Set(supportedCodecs.map((c) => normalizeAudioCodec(c)).filter(Boolean));
  if (supported.has(normalized)) return true;

  // Alias / compound labels (e.g. "truehd atmos", "eac3_joc").
  for (const entry of supported) {
    if (!entry) continue;
    if (normalized.includes(entry) || entry.includes(normalized)) return true;
  }

  // AC-3 family: advertising eac3 implies ac3 is fine; advertising ac3 does not imply eac3.
  if (normalized === "ac3" && (supported.has("eac3") || supported.has("ec3"))) return true;
  if ((normalized === "eac3" || normalized === "ec3") && supported.has("eac3")) return true;

  return false;
}

/** Default / primary audio track for a file version. */
export function primaryAudioCodec(version: FileVersion | null | undefined): string | null {
  if (!version) return null;
  if (version.codec_audio?.trim()) return version.codec_audio;
  const tracks = version.audio_tracks ?? [];
  if (!tracks.length) return null;
  const preferred = tracks.find((t) => t.default) ?? tracks[0];
  return preferred?.codec ?? null;
}

/**
 * True when this file's primary audio is NOT in the TV's advertised set —
 * Prairie should remux (often with audio→AAC) rather than Direct Play.
 * Callers should prefer advertising accurate `codecs_audio` and letting the
 * server decide; this helper is for UI / diagnostics only.
 */
export function versionNeedsAudioRemux(
  version: FileVersion | null | undefined,
  supportedCodecs: readonly string[],
): boolean {
  if (!version) return false;
  const primary = primaryAudioCodec(version);
  if (!primary) return false;
  return !isAudioCodecSupported(primary, supportedCodecs);
}

export function watchFileNeedsAudioRemux(
  watch: WatchDetail | null | undefined,
  fileId: number,
  supportedCodecs: readonly string[],
): boolean {
  if (!watch) return false;
  return versionNeedsAudioRemux(selectFileVersion(watch, fileId), supportedCodecs);
}
