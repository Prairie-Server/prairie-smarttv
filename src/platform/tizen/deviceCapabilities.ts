import { isAvPlayAvailable } from "./avplay";
import { DEFAULT_TV_CAPABILITIES } from "../../player/types";

export interface TvPlaybackCapabilities {
  codecs_video: string[];
  codecs_audio: string[];
  containers: string[];
  max_resolution: string;
  hdr: boolean;
}

function tizenMajorVersion(): number {
  const ua = navigator.userAgent ?? "";
  const match = ua.match(/Tizen[/\s](\d+)/i);
  return match ? Number(match[1]) : 0;
}

function probeMaxResolution(): string {
  const width = Math.max(screen.width || 0, window.innerWidth || 0);
  const height = Math.max(screen.height || 0, window.innerHeight || 0);
  if (height >= 2160 || width >= 3840) return "2160p";
  if (height >= 1440 || width >= 2560) return "1440p";
  if (height >= 1080 || width >= 1920) return "1080p";
  return "720p";
}

function probeHdr(tizenMajor: number): boolean {
  try {
    if (typeof window.matchMedia === "function" && window.matchMedia("(dynamic-range: high)").matches) {
      return true;
    }
  } catch {
    /* ignore */
  }
  // HDR is common on Tizen 4+ panels; keep false on unknown/low versions.
  return tizenMajor >= 4;
}

/**
 * Probe what this TV can likely Direct Play. Falls back to DEFAULT_TV_CAPABILITIES
 * fields when the runtime cannot be inspected (unit tests / browser).
 */
export function probeTvPlaybackCapabilities(
  input: { avplayAvailable?: boolean } = {},
): TvPlaybackCapabilities {
  const avplay = input.avplayAvailable ?? isAvPlayAvailable();
  const tizenMajor = tizenMajorVersion();

  const codecs_video = ["h264"];
  // HEVC Direct Play is reliable on modern Tizen with AVPlay.
  if (avplay || tizenMajor >= 3) {
    codecs_video.push("hevc");
  }

  const codecs_audio = [...DEFAULT_TV_CAPABILITIES.codecs_audio];
  // Prefer progressive containers AVPlay handles well; keep mkv when native player exists.
  const containers = avplay ? ["mp4", "mpegts", "hls", "mkv"] : ["mp4", "mpegts", "hls"];

  return {
    codecs_video,
    codecs_audio,
    containers,
    max_resolution: probeMaxResolution(),
    hdr: probeHdr(tizenMajor),
  };
}
