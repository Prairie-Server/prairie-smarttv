import type { FileVersion, WatchDetail } from "../api/watch";
import { selectFileVersion } from "../api/watch";

/** Audio codecs Tizen/webOS AVPlay can typically Direct Play / remux-copy. */
const TV_SAFE_AUDIO = new Set(["aac", "mp3", "ac3", "eac3", "ec3", "mp2", "mpa"]);

function normalizeCodec(raw: string | null | undefined): string {
  return (raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

export function isTvSafeAudioCodec(codec: string | null | undefined): boolean {
  const normalized = normalizeCodec(codec);
  if (!normalized) return true;
  if (TV_SAFE_AUDIO.has(normalized)) return true;
  // Catch compound labels like "eac3atmos" after normalization.
  if (normalized.includes("eac3") || normalized.endsWith("ac3")) return true;
  return false;
}

/**
 * TrueHD / DTS / FLAC / Atmos TrueHD need a decode → AAC (or similar) ladder
 * on Smart TV. Prefer forced transcode up front instead of remux-copy.
 */
export function requiresForcedTranscodeAudio(codec: string | null | undefined): boolean {
  const normalized = normalizeCodec(codec);
  if (!normalized) return false;
  if (normalized.includes("truehd") || normalized === "mlp" || normalized === "mlpa") {
    return true;
  }
  if (normalized.includes("dts")) return true;
  if (normalized === "flac" || normalized === "alac" || normalized === "opus") return true;
  if (normalized.includes("pcm") || normalized === "lpcm") return true;
  return !isTvSafeAudioCodec(normalized);
}

export function versionRequiresForcedTranscode(version: FileVersion | null | undefined): boolean {
  if (!version) return false;
  if (requiresForcedTranscodeAudio(version.codec_audio)) return true;
  const tracks = version.audio_tracks ?? [];
  if (!tracks.length) return false;
  // If the default (or first) track is unsafe, force transcode.
  const defaultTrack = tracks.find((t) => t.default) ?? tracks[0];
  return requiresForcedTranscodeAudio(defaultTrack?.codec);
}

export function watchFileRequiresForcedTranscode(
  watch: WatchDetail | null | undefined,
  fileId: number,
): boolean {
  if (!watch) return false;
  return versionRequiresForcedTranscode(selectFileVersion(watch, fileId));
}
